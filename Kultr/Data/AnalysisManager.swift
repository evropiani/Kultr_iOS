import AVFoundation
import Foundation
import Observation

/** Longest track worth analysing; DJ mixes and audiobooks do not need InjeKt. */
let MAX_ANALYSIS_SECONDS = 20 * 60

struct AnalysisProgress: Hashable {
    let done: Int
    let total: Int
    let current: String
}

/** At most [limit] pieces of work at once. */
actor AsyncSemaphore {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(_ limit: Int) {
        available = limit
    }

    func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            available += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/**
 * InjeKt's analysis: decode a track once (at a low bitrate, or from the offline
 * copy), measure tempo, key, energy and structure, and cache the numbers.
 */
@MainActor
@Observable
final class AnalysisManager {
    private(set) var bulkProgress: AnalysisProgress?

    @ObservationIgnored private unowned let graph: AppGraph
    @ObservationIgnored private var inFlight: [String: Task<TrackAnalysis?, Never>] = [:]
    /** Decoding is heavy; never more than two at once. */
    @ObservationIgnored private let permits = AsyncSemaphore(2)
    @ObservationIgnored private var bulkTask: Task<Void, Never>?

    init(graph: AppGraph) {
        self.graph = graph
    }

    func analysedCount() async -> Int {
        await graph.library.read(0) { $0.analysisCount(version: ANALYSIS_VERSION) }
    }

    func missingCount() async -> Int {
        await graph.library.read(0) { $0.missingAnalysisCount(version: ANALYSIS_VERSION, maxSeconds: MAX_ANALYSIS_SECONDS) }
    }

    func cached(_ songId: String) async -> TrackAnalysis? {
        await graph.library.read(nil) { db in db.analysis(songId).flatMap { $0.isCurrent ? $0 : nil } }
    }

    func cachedMany(_ ids: [String]) async -> [String: TrackAnalysis] {
        await graph.library.read([:]) { db in
            var out: [String: TrackAnalysis] = [:]
            for analysis in db.analyses(ids) where analysis.isCurrent { out[analysis.songId] = analysis }
            return out
        }
    }

    /** Cached analysis, or analyse now. Concurrent requests for one track share the work. */
    func getOrAnalyse(_ song: Song, force: Bool = false) async -> TrackAnalysis? {
        if song.isRadio { return nil }
        if !force, let cached = await cached(song.id) { return cached }
        if let existing = inFlight[song.id] { return await existing.value }
        let permits = self.permits
        let task = Task<TrackAnalysis?, Never> { [weak self] in
            await permits.acquire()
            defer { Task { await permits.release() } }
            guard let self, !Task.isCancelled else { return nil }
            return await self.analyse(song)
        }
        inFlight[song.id] = task
        let result = await task.value
        inFlight[song.id] = nil
        return result
    }

    /** Warm the cache for a track that is about to play. Fire and forget. */
    func analyseAhead(_ song: Song) {
        let s = graph.settings.current
        guard s.injektEnabled, s.injektAnalyseAhead, !song.isRadio else { return }
        Task { _ = await getOrAnalyse(song) }
    }

    private func analyse(_ song: Song) async -> TrackAnalysis? {
        guard let db = graph.library.db else { return nil }
        if (song.duration ?? 0) > MAX_ANALYSIS_SECONDS { return nil }
        let local = graph.offline.fileFor(song.id)
        if local == nil && graph.settings.current.injektAnalyseOnWifiOnly && graph.network.isMetered { return nil }
        guard let client = graph.auth.client else { return nil }
        let session = graph.auth.session
        let streamUrl = client.streamUrl(song.id, maxBitRate: ANALYSIS_BITRATE, format: "mp3")

        return await Task.detached(priority: .utility) { () -> TrackAnalysis? in
            var temp: URL?
            defer { if let temp { try? FileManager.default.removeItem(at: temp) } }
            do {
                let source: URL
                if let local {
                    source = local
                } else {
                    guard let streamUrl else { return nil }
                    let (downloaded, response) = try await session.download(from: streamUrl)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
                    let target = FileManager.default.temporaryDirectory.appendingPathComponent("analysis-\(UUID().uuidString).mp3")
                    try FileManager.default.moveItem(at: downloaded, to: target)
                    temp = target
                    source = target
                }
                guard let decoded = AudioDecoder.decodeToMono(source, maxSeconds: MAX_ANALYSIS_SECONDS),
                      decoded.0.count >= decoded.1 * 5
                else { return nil }
                let analysis = TrackAnalysis.from(song: song, pcm: analysePcm(decoded.0, sampleRate: decoded.1))
                try db.putAnalysis(analysis)
                return analysis
            } catch {
                return nil
            }
        }.value
    }

    /** "Analyse missing": work through every track without current analysis. */
    func startBulk() {
        guard bulkTask == nil else { return }
        graph.messages.show("Analysing tracks in the background.")
        bulkTask = Task { [weak self] in
            guard let self else { return }
            var done = 0
            var skipped = Set<String>()
            while !Task.isCancelled {
                if self.graph.settings.current.injektAnalyseOnWifiOnly && self.graph.network.isMetered { break }
                let limit = 50 + skipped.count
                let batch = await self.graph.library.read([Song]()) { db in
                    db.missingAnalysis(version: ANALYSIS_VERSION, maxSeconds: MAX_ANALYSIS_SECONDS, limit: limit)
                }.filter { !skipped.contains($0.id) }
                if batch.isEmpty { break }
                let total = done + batch.count
                for song in batch {
                    if Task.isCancelled { break }
                    self.bulkProgress = AnalysisProgress(done: done, total: total, current: song.title)
                    if await self.getOrAnalyse(song) == nil { skipped.insert(song.id) }
                    done += 1
                }
            }
            self.bulkProgress = nil
            self.bulkTask = nil
            if done > 0 && !Task.isCancelled { self.graph.messages.success("InjeKt analysis finished (\(done) tracks).") }
        }
    }

    func cancelBulk() {
        bulkTask?.cancel()
        bulkTask = nil
        bulkProgress = nil
    }

    var bulkRunning: Bool { bulkTask != nil }
}

/** Decode any audio file iOS understands into mono PCM at ~22 kHz. */
enum AudioDecoder {
    static func decodeToMono(_ url: URL, maxSeconds: Int) -> ([Float], Int)? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let rate = Int(format.sampleRate)
        let channels = Int(format.channelCount)
        guard rate > 0, channels > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32768)
        else { return nil }
        let accumulator = MonoAccumulator(inputRate: rate, channels: channels)
        let limit = maxSeconds * accumulator.sampleRate
        while accumulator.length < limit {
            do {
                try file.read(into: buffer)
            } catch {
                break
            }
            let frames = Int(buffer.frameLength)
            if frames == 0 { break }
            guard let data = buffer.floatChannelData else { return nil }
            if format.isInterleaved {
                accumulator.addFloat(Array(UnsafeBufferPointer(start: data[0], count: frames * channels)))
            } else {
                let pointers = (0..<channels).map { UnsafePointer(data[$0]) }
                accumulator.addPlanar(pointers, frames: frames)
            }
        }
        return (accumulator.toArray(), accumulator.sampleRate)
    }
}
