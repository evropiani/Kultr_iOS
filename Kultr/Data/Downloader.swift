import Foundation

/**
 * File downloads with progress, on top of URLSession's download tasks. The
 * finished file is moved to its destination before the call returns.
 */
final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private final class Job {
        let destination: URL
        let progress: (Int64, Int64) -> Void
        let continuation: CheckedContinuation<(Int64, HTTPURLResponse?), Error>
        var moved: Result<Int64, Error>?

        init(destination: URL, progress: @escaping (Int64, Int64) -> Void, continuation: CheckedContinuation<(Int64, HTTPURLResponse?), Error>) {
            self.destination = destination
            self.progress = progress
            self.continuation = continuation
        }
    }

    private let lock = NSLock()
    private var jobs: [Int: Job] = [:]
    private var session: URLSession!

    init(allowsExpensiveNetworkAccess: Bool) {
        super.init()
        let config = URLSessionConfiguration.default
        config.allowsExpensiveNetworkAccess = allowsExpensiveNetworkAccess
        config.allowsConstrainedNetworkAccess = allowsExpensiveNetworkAccess
        config.timeoutIntervalForRequest = 60
        config.httpAdditionalHeaders = ["User-Agent": "Kultr-iOS/\(appVersion)"]
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func invalidate() {
        session.invalidateAndCancel()
    }

    /** Download [url] to [destination]; returns its size and the HTTP response. */
    func download(_ url: URL, to destination: URL, progress: @escaping (Int64, Int64) -> Void) async throws -> (Int64, HTTPURLResponse?) {
        let task = session.downloadTask(with: url)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                jobs[task.taskIdentifier] = Job(destination: destination, progress: progress, continuation: continuation)
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    private func job(_ task: URLSessionTask) -> Job? {
        lock.lock()
        defer { lock.unlock() }
        return jobs[task.taskIdentifier]
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        job(downloadTask)?.progress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let job = job(downloadTask) else { return }
        // The temporary file is deleted when this returns, so move it now.
        do {
            let http = downloadTask.response as? HTTPURLResponse
            if let http, !(200..<300).contains(http.statusCode) {
                throw NetworkError(message: "HTTP \(http.statusCode)")
            }
            if let type = http?.value(forHTTPHeaderField: "Content-Type"), type.contains("json") || type.contains("xml") {
                throw NetworkError(message: "The server refused the download.")
            }
            let manager = FileManager.default
            if manager.fileExists(atPath: job.destination.path) { try manager.removeItem(at: job.destination) }
            try manager.moveItem(at: location, to: job.destination)
            let size = (try? manager.attributesOfItem(atPath: job.destination.path)[.size] as? NSNumber)?.int64Value ?? 0
            job.moved = .success(size)
        } catch {
            job.moved = .failure(error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let job = jobs.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        guard let job else { return }
        if let error {
            if (error as? URLError)?.code == .cancelled {
                job.continuation.resume(throwing: CancellationError())
            } else {
                job.continuation.resume(throwing: error)
            }
            return
        }
        switch job.moved {
        case .success(let size): job.continuation.resume(returning: (size, task.response as? HTTPURLResponse))
        case .failure(let error): job.continuation.resume(throwing: error)
        case nil: job.continuation.resume(throwing: NetworkError(message: "The download did not finish."))
        }
    }
}
