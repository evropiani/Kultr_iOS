import AVFoundation
import Foundation
import UniformTypeIdentifiers

/**
 * Recently streamed audio, kept on disk so replays and seeks do not refetch.
 * Least recently used files go first once the cache is over its size.
 */
final class StreamCache: @unchecked Sendable {
    static let shared = StreamCache()

    let directory: URL
    private let lock = NSLock()
    private var limitBytes: Int64 = 1024 * 1024 * 1024

    private init() {
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("stream", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func setLimit(megabytes: Int) {
        lock.lock()
        limitBytes = Int64(min(16_384, max(64, megabytes))) * 1024 * 1024
        lock.unlock()
    }

    func location(for key: String, fileExtension: String) -> URL {
        directory.appendingPathComponent("\(md5Hex(key)).\(fileExtension)")
    }

    /** A complete cached copy, touched so it counts as recently used. */
    func hit(for key: String, fileExtension: String) -> URL? {
        let url = location(for: key, fileExtension: fileExtension)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return url
    }

    func store(_ file: URL, as target: URL) {
        let manager = FileManager.default
        try? manager.removeItem(at: target)
        guard (try? manager.copyItem(at: file, to: target)) != nil else { return }
        trim()
    }

    func trim() {
        lock.lock()
        let limit = limitBytes
        lock.unlock()
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return }
        var entries = files.compactMap { url -> (URL, Int64, Date)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(Int64(0)) { $0 + $1.1 }
        entries.sort { $0.2 < $1.2 }
        for entry in entries where total > limit {
            try? FileManager.default.removeItem(at: entry.0)
            total -= entry.1
        }
    }

    func clear() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files { try? FileManager.default.removeItem(at: file) }
    }
}

/** The uniform type AVFoundation needs for a file with this suffix or MIME type. */
func audioTypeIdentifier(suffix: String?, mimeType: String?) -> String {
    if let suffix, !suffix.isEmpty {
        switch suffix.lowercased() {
        case "mp3": return UTType.mp3.identifier
        case "m4a", "m4b", "mp4", "alac": return UTType.mpeg4Audio.identifier
        case "aac": return "public.aac-audio"
        case "flac": return "org.xiph.flac"
        case "wav": return UTType.wav.identifier
        case "aif", "aiff": return UTType.aiff.identifier
        default: if let type = UTType(filenameExtension: suffix) { return type.identifier }
        }
    }
    if let mimeType, let type = UTType(mimeType: mimeType) { return type.identifier }
    return UTType.mp3.identifier
}

/**
 * Streams one track to AVPlayer through a resource loader: the file is
 * fetched from the start once, written to a temporary file as it arrives,
 * and AVPlayer's range requests are answered from it. Requests far ahead of
 * the download (a seek, or a peek at the end of the file) get a ranged fetch
 * of their own. When the whole file has arrived it goes into [StreamCache].
 */
final class StreamingResource: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate, @unchecked Sendable {
    static let scheme = "kultr-stream"

    let asset: AVURLAsset
    private let remoteURL: URL
    private let contentType: String
    private let cacheTarget: URL?
    private let userAgent: String

    private let queue = DispatchQueue(label: "kultr.stream")
    private var session: URLSession?
    private var mainTask: URLSessionDataTask?
    private let tempURL: URL
    private var writer: FileHandle?
    private var reader: FileHandle?
    private var received: Int64 = 0
    private var expected: Int64 = -1
    private var headersSeen = false
    private var finished = false
    private var failure: Error?
    private var invalidated = false
    private var pending: [AVAssetResourceLoadingRequest] = []

    private final class RangeFetch {
        let request: AVAssetResourceLoadingRequest
        let start: Int64
        var skip: Int64 = 0
        var checked = false
        init(request: AVAssetResourceLoadingRequest, start: Int64) {
            self.request = request
            self.start = start
        }
    }

    private var ranges: [Int: RangeFetch] = [:]

    /** Requests this far beyond the download get a ranged fetch instead of waiting. */
    private static let farAhead: Int64 = 768 * 1024

    init(remoteURL: URL, contentType: String, cacheTarget: URL?, userAgent: String) {
        self.remoteURL = remoteURL
        self.contentType = contentType
        self.cacheTarget = cacheTarget
        self.userAgent = userAgent
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("stream-\(UUID().uuidString)")
        var components = URLComponents(url: remoteURL, resolvingAgainstBaseURL: false)
        components?.scheme = Self.scheme
        asset = AVURLAsset(url: components?.url ?? remoteURL)
        super.init()
        asset.resourceLoader.setDelegate(self, queue: queue)
    }

    /** Stop everything and delete the partial file. */
    func invalidate() {
        queue.async { [self] in
            guard !invalidated else { return }
            invalidated = true
            session?.invalidateAndCancel()
            session = nil
            for request in pending where !request.isFinished && !request.isCancelled {
                request.finishLoading(with: URLError(.cancelled))
            }
            pending = []
            ranges = [:]
            try? writer?.close()
            try? reader?.close()
            writer = nil
            reader = nil
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    // ------------------------------------------------------------ loader --

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        if invalidated { return false }
        startIfNeeded()
        pending.append(loadingRequest)
        serve()
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        pending.removeAll { $0 === loadingRequest }
        for (id, fetch) in ranges where fetch.request === loadingRequest {
            ranges[id] = nil
            session?.getAllTasks { tasks in tasks.first { $0.taskIdentifier == id }?.cancel() }
        }
    }

    private func makeRequest(range: Int64? = nil) -> URLRequest {
        var request = URLRequest(url: remoteURL)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let range { request.setValue("bytes=\(range)-", forHTTPHeaderField: "Range") }
        return request
    }

    private func startIfNeeded() {
        guard session == nil, !invalidated else { return }
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        writer = try? FileHandle(forWritingTo: tempURL)
        reader = try? FileHandle(forReadingFrom: tempURL)
        let operations = OperationQueue()
        operations.maxConcurrentOperationCount = 1
        operations.underlyingQueue = queue
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: operations)
        self.session = session
        let task = session.dataTask(with: makeRequest())
        mainTask = task
        task.resume()
    }

    private func fillContentInfo(_ request: AVAssetResourceLoadingRequest) -> Bool {
        guard let info = request.contentInformationRequest else { return true }
        guard headersSeen, expected > 0 || finished else { return false }
        info.contentType = contentType
        info.contentLength = expected > 0 ? expected : received
        info.isByteRangeAccessSupported = true
        return true
    }

    private func readFile(_ offset: Int64, _ length: Int) -> Data? {
        guard let reader, length > 0 else { return nil }
        do {
            try reader.seek(toOffset: UInt64(offset))
            return try reader.read(upToCount: length)
        } catch {
            return nil
        }
    }

    /** Answer whatever can be answered from the downloaded bytes. */
    private func serve() {
        guard !invalidated else { return }
        var done: [AVAssetResourceLoadingRequest] = []
        for request in pending {
            if request.isCancelled || request.isFinished {
                done.append(request)
                continue
            }
            if let failure {
                request.finishLoading(with: failure)
                done.append(request)
                continue
            }
            guard fillContentInfo(request) else { continue }
            guard let data = request.dataRequest else {
                request.finishLoading()
                done.append(request)
                continue
            }
            if ranges.values.contains(where: { $0.request === request }) { continue }
            let length = expected > 0 ? expected : (finished ? received : Int64.max)
            let end = data.requestsAllDataToEndOfResource ? length : min(length, data.requestedOffset + Int64(data.requestedLength))
            while data.currentOffset < min(end, received) {
                let count = Int(min(min(end, received) - data.currentOffset, 512 * 1024))
                guard let chunk = readFile(data.currentOffset, count), !chunk.isEmpty else { break }
                data.respond(with: chunk)
            }
            if data.currentOffset >= end || (finished && data.currentOffset >= received) {
                request.finishLoading()
                done.append(request)
            } else if !finished && data.currentOffset > received + Self.farAhead {
                startRange(for: request, at: data.currentOffset)
            }
        }
        if !done.isEmpty { pending.removeAll { req in done.contains { $0 === req } } }
    }

    private func startRange(for request: AVAssetResourceLoadingRequest, at offset: Int64) {
        guard let session else { return }
        let task = session.dataTask(with: makeRequest(range: offset))
        ranges[task.taskIdentifier] = RangeFetch(request: request, start: offset)
        task.resume()
    }

    // ----------------------------------------------------------- network --

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 200
        let type = http?.value(forHTTPHeaderField: "Content-Type") ?? ""
        let refused = !(200..<300).contains(status) || type.contains("json") || type.contains("xml")
        if dataTask === mainTask {
            headersSeen = true
            if refused {
                failure = NetworkError(message: "The server refused to stream this track (HTTP \(status)).")
                completionHandler(.cancel)
                serve()
                return
            }
            expected = response.expectedContentLength
            completionHandler(.allow)
            serve()
            return
        }
        if let fetch = ranges[dataTask.taskIdentifier] {
            if refused {
                ranges[dataTask.taskIdentifier] = nil
                completionHandler(.cancel)
                serve()
                return
            }
            // A server that ignores Range sends the whole file again; skip to our offset.
            fetch.skip = status == 206 ? 0 : fetch.start
            completionHandler(.allow)
            return
        }
        completionHandler(.cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if dataTask === mainTask {
            _ = try? writer?.seekToEnd()
            try? writer?.write(contentsOf: data)
            received += Int64(data.count)
            serve()
            return
        }
        guard let fetch = ranges[dataTask.taskIdentifier], let dataRequest = fetch.request.dataRequest else { return }
        var chunk = data
        if fetch.skip > 0 {
            let drop = Int(min(fetch.skip, Int64(chunk.count)))
            chunk = chunk.dropFirst(drop)
            fetch.skip -= Int64(drop)
            if chunk.isEmpty { return }
        }
        if fetch.request.isCancelled || fetch.request.isFinished {
            ranges[dataTask.taskIdentifier] = nil
            dataTask.cancel()
            return
        }
        dataRequest.respond(with: Data(chunk))
        let end = dataRequest.requestsAllDataToEndOfResource
            ? (expected > 0 ? expected : Int64.max)
            : dataRequest.requestedOffset + Int64(dataRequest.requestedLength)
        if dataRequest.currentOffset >= end {
            fetch.request.finishLoading()
            pending.removeAll { $0 === fetch.request }
            ranges[dataTask.taskIdentifier] = nil
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if task === mainTask {
            if let error {
                if failure == nil && (error as? URLError)?.code != .cancelled { failure = error }
            } else {
                finished = true
                if expected <= 0 { expected = received }
                commitToCache()
            }
            serve()
            return
        }
        guard let fetch = ranges.removeValue(forKey: task.taskIdentifier) else { return }
        if !fetch.request.isFinished && !fetch.request.isCancelled {
            if let error, (error as? URLError)?.code != .cancelled {
                fetch.request.finishLoading(with: error)
            } else {
                fetch.request.finishLoading()
            }
            pending.removeAll { $0 === fetch.request }
        }
    }

    private func commitToCache() {
        guard let cacheTarget, received > 0 else { return }
        try? writer?.synchronize()
        // On this queue, so the file cannot be deleted by invalidate() mid-copy.
        StreamCache.shared.store(tempURL, as: cacheTarget)
    }
}
