import Foundation
import Observation
import UIKit

struct DownloadProgress: Hashable {
    var done: Int
    var total: Int
    var failed: Int
    var bytes: Int64
    var current: String
}

/** A file being fetched right now. [total] is an estimate when the server does not say. */
struct ActiveDownload: Hashable {
    let song: Song
    let bytes: Int64
    let total: Int64

    var fraction: Double { total > 0 ? min(1, max(0, Double(bytes) / Double(total))) : 0 }
}

/** What the download queue is doing, for the indicator and the Downloads page. */
enum DownloadStatus: Equatable {
    case idle
    /** Tracks are queued but cannot be fetched yet: no network, or no Wi-Fi when that is required. */
    case waiting(queued: Int, forWifi: Bool)
    case running(progress: DownloadProgress?, queued: Int)
}

/**
 * Offline copies. Downloads are *incremental*: asking for the same albums
 * again only fetches what is missing, including files deleted behind our back.
 *
 * Requests go into the database as queued rows and a worker drains them
 * while Kultr is open or playing; whatever is left resumes next time.
 */
@MainActor
@Observable
final class OfflineManager {
    private(set) var downloadedIds: Set<String> = []
    private(set) var queuedCount = 0
    private(set) var progress: DownloadProgress?
    private(set) var active: [String: ActiveDownload] = [:]
    private(set) var status: DownloadStatus = .idle

    @ObservationIgnored private unowned let graph: AppGraph
    /** songId → file name, for the active server. */
    @ObservationIgnored private var paths: [String: String] = [:]
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var workerWifiOnly: Bool?
    @ObservationIgnored private var restartWhenDone = false
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init(graph: AppGraph) {
        self.graph = graph
    }

    /** Called once the rest of the graph exists. */
    func start() {
        graph.settings.observe { [weak self] old, new in
            // Changing "Wi-Fi only" must apply to downloads already waiting.
            if old.offlineWifiOnly != new.offlineWifiOnly, let self, self.queuedCount > 0 { self.startWorker(force: true) }
        }
        graph.network.observe { [weak self] in
            guard let self else { return }
            if self.queuedCount > 0 { self.startWorker() } else { self.refreshStatus() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.queuedCount > 0 else { return }
                self.startWorker()
            }
        }
        reload()
    }

    /** Re-read the download table for the active server; resumes a queue left behind. */
    func reload() {
        guard let db = graph.library.db else {
            paths = [:]
            downloadedIds = []
            queuedCount = 0
            refreshStatus()
            return
        }
        let rows = db.doneDownloads()
        var map: [String: String] = [:]
        for row in rows { if let path = row.path { map[row.songId] = path } }
        paths = map
        downloadedIds = Set(map.keys)
        queuedCount = db.queuedCount()
        refreshStatus()
        if queuedCount > 0 && worker == nil { startWorker() }
    }

    private func refreshCounts() {
        guard let db = graph.library.db else { return }
        queuedCount = db.queuedCount()
        refreshStatus()
    }

    private func refreshStatus() {
        let wifiOnly = graph.settings.current.offlineWifiOnly
        if worker != nil && allowed() {
            status = .running(progress: progress, queued: queuedCount)
        } else if queuedCount > 0 {
            status = .waiting(queued: queuedCount, forWifi: graph.network.isOnline && wifiOnly && graph.network.isMetered)
        } else {
            status = .idle
        }
    }

    private func allowed() -> Bool {
        let network = graph.network
        if !network.isOnline { return false }
        if graph.settings.current.offlineWifiOnly && network.isMetered { return false }
        return true
    }

    // ---------------------------------------------------------------- files --

    static func directoryFor(_ profileId: String) -> URL {
        let url = LibraryRepository.directory
            .appendingPathComponent("offline", isDirectory: true)
            .appendingPathComponent(String(md5Hex(profileId).prefix(16)), isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            var excluded = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? excluded.setResourceValues(values)
        }
        return url
    }

    private var directory: URL? {
        graph.auth.active.map { Self.directoryFor($0.id) }
    }

    /** The stored file for a song, if there is one and it still exists. */
    func fileFor(_ songId: String) -> URL? {
        guard let name = paths[songId], let directory else { return nil }
        let url = directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func deleteDataFor(_ profileId: String) {
        try? FileManager.default.removeItem(at: Self.directoryFor(profileId))
    }

    /** How many of [songs] are not downloaded yet — used to label buttons. */
    func missing(_ songs: [Song]) -> Int {
        songs.filter { !$0.isRadio && !downloadedIds.contains($0.id) }.count
    }

    // -------------------------------------------------------------- requests --

    func download(_ songs: [Song], label: String? = nil) async {
        guard let db = graph.library.db, let directory else { return }
        var seen = Set<String>()
        let wanted = songs.filter { !$0.isRadio && seen.insert($0.id).inserted }
        let ids = wanted.map { $0.id }
        let pending: [Song] = await Task.detached(priority: .userInitiated) {
            let rows = Dictionary(db.downloads(ids).map { ($0.songId, $0) }, uniquingKeysWith: { a, _ in a })
            return wanted.filter { song in
                guard let row = rows[song.id], row.state == DownloadState.done, let path = row.path else { return true }
                return !FileManager.default.fileExists(atPath: directory.appendingPathComponent(path).path)
            }
        }.value
        if pending.isEmpty {
            graph.messages.success(label.map { "\($0) is already downloaded." } ?? "Everything is already downloaded.")
            return
        }
        let now = Format.nowMs()
        let rows = pending.enumerated().map { i, song in
            // Keep the order they were asked for: albums download track by track.
            DownloadRow(songId: song.id, state: DownloadState.queued, path: nil, size: 0, contentType: nil, requestedAt: now + Int64(i), savedAt: nil, error: nil)
        }
        await Task.detached(priority: .userInitiated) {
            for chunk in rows.chunked(SQL_CHUNK) { try? db.upsertDownloads(chunk) }
        }.value
        refreshCounts()
        startWorker()
        let skipped = wanted.count - pending.count
        var text = "Downloading \(pending.count) track\(pending.count == 1 ? "" : "s")"
        if skipped > 0 { text += " · \(skipped) already here" }
        if graph.settings.current.offlineWifiOnly && graph.network.isMetered { text += " · waiting for Wi-Fi" }
        graph.messages.show(text)
    }

    /**
     * Make sure a worker is draining the queue under the current Wi-Fi rule.
     * A worker already running with the same rule picks up anything queued
     * at the last moment; one made under the other rule is replaced.
     */
    func startWorker(force: Bool = false) {
        let wifiOnly = graph.settings.current.offlineWifiOnly
        if let worker {
            if force || workerWifiOnly != wifiOnly {
                worker.cancel()
                self.worker = nil
            } else {
                restartWhenDone = true
                return
            }
        }
        guard allowed() else {
            refreshStatus()
            return
        }
        workerWifiOnly = wifiOnly
        beginBackgroundTime()
        worker = Task { [weak self] in
            await self?.drain()
            guard let self else { return }
            self.worker = nil
            self.progress = nil
            self.active = [:]
            self.refreshCounts()
            if self.restartWhenDone {
                self.restartWhenDone = false
                if self.queuedCount > 0 && self.allowed() { self.startWorker() }
            }
            self.endBackgroundTime()
        }
        refreshStatus()
    }

    private func beginBackgroundTime() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "kultr.downloads") { [weak self] in
            MainActor.assumeIsolated {
                // Out of time: stop cleanly; what is left stays queued for next time.
                self?.worker?.cancel()
                self?.endBackgroundTime()
            }
        }
    }

    private func endBackgroundTime() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func drain() async {
        guard let db = graph.library.db, let client = graph.auth.client, let directory else { return }
        let settings = graph.settings.current
        let concurrency = min(8, max(1, settings.offlineConcurrency))
        let downloader = Downloader(allowsExpensiveNetworkAccess: !settings.offlineWifiOnly)
        defer { downloader.invalidate() }
        var done = 0
        var failed = 0
        var bytes: Int64 = 0

        while !Task.isCancelled {
            guard allowed() else { break }
            let batch = db.queuedDownloads(32)
            if batch.isEmpty { break }
            var total = done + failed + db.queuedCount()
            progress = DownloadProgress(done: done, total: total, failed: failed, bytes: bytes, current: "")
            refreshStatus()
            await withTaskGroup(of: (String, Int64).self) { group in
                var nextIndex = 0
                var running = 0
                while nextIndex < batch.count && running < concurrency {
                    let row = batch[nextIndex]
                    nextIndex += 1
                    running += 1
                    group.addTask { [weak self] in
                        guard let self else { return (row.songId, -1) }
                        return (row.songId, await self.fetch(row, db: db, client: client, directory: directory, downloader: downloader, settings: settings))
                    }
                }
                while running > 0 {
                    guard let finished = await group.next() else { break }
                    running -= 1
                    let (songId, result) = finished
                    if result >= 0 {
                        done += 1
                        bytes += result
                    } else if !Task.isCancelled {
                        failed += 1
                    }
                    total = max(total, done + failed)
                    progress = DownloadProgress(done: done, total: total, failed: failed, bytes: bytes, current: songId)
                    refreshStatus()
                    if !Task.isCancelled && nextIndex < batch.count {
                        let row = batch[nextIndex]
                        nextIndex += 1
                        running += 1
                        group.addTask { [weak self] in
                            guard let self else { return (row.songId, -1) }
                            return (row.songId, await self.fetch(row, db: db, client: client, directory: directory, downloader: downloader, settings: settings))
                        }
                    }
                }
            }
            reload()
        }
        if done + failed > 0 && !Task.isCancelled {
            graph.messages.show(
                failed == 0 ? "Downloaded \(done) track\(done == 1 ? "" : "s")." : "Downloaded \(done), \(failed) failed.",
                failed == 0 ? .success : .warning
            )
        }
    }

    /** Download one track; returns its size, or -1 on failure. */
    private func fetch(
        _ row: DownloadRow,
        db: LibraryDatabase,
        client: SubsonicClient,
        directory: URL,
        downloader: Downloader,
        settings: Settings
    ) async -> Int64 {
        var song = db.song(row.songId)
        if song == nil { song = try? await client.getSong(row.songId) }
        defer { active[row.songId] = nil }
        do {
            guard let song else { throw NetworkError(message: "This track is no longer on the server.") }
            let transcode = settings.offlineBitrate > 0
            let format = playableFormat(settings.preferredFormat)
            guard let url = transcode ? client.streamUrl(song.id, maxBitRate: settings.offlineBitrate, format: format) : client.downloadUrl(song.id) else {
                throw NetworkError(message: "Not signed in.")
            }
            let suffix = transcode ? format : ((song.suffix ?? "").isEmpty ? "audio" : song.suffix!)
            let safeId = song.id.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
            let name = "\(safeId).\(suffix)"
            let target = directory.appendingPathComponent(name)
            let estimate = Self.estimateSize(song, transcode ? settings.offlineBitrate : nil)
            active[song.id] = ActiveDownload(song: song, bytes: 0, total: estimate)
            let (size, _) = try await downloader.download(url, to: target) { [weak self] written, expected in
                let totalBytes = expected > 0 ? expected : max(estimate, written)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.active[song.id] != nil else { return }
                        self.active[song.id] = ActiveDownload(song: song, bytes: written, total: totalBytes)
                    }
                }
            }
            var saved = row
            saved.state = DownloadState.done
            saved.path = name
            saved.size = size
            saved.contentType = song.contentType
            saved.savedAt = Format.nowMs()
            saved.error = nil
            try db.upsertDownloads([saved])
            paths[song.id] = name
            downloadedIds.insert(song.id)
            return size
        } catch {
            if error is CancellationError || Task.isCancelled { return -1 }
            var failedRow = row
            failedRow.state = DownloadState.failed
            failedRow.error = describeError(error)
            try? db.upsertDownloads([failedRow])
            return -1
        }
    }

    /** A size guess for a progress bar when the server sends no length (transcoding). */
    private static func estimateSize(_ song: Song, _ transcodeKbps: Int?) -> Int64 {
        if transcodeKbps == nil, let size = song.size, size > 0 { return size }
        guard let seconds = song.duration else { return 0 }
        let kbps = transcodeKbps ?? song.bitRate ?? 320
        return Int64(seconds) * Int64(kbps) * 1000 / 8
    }

    // ---------------------------------------------------------- queue edits --

    /** Stop downloading and forget everything still queued. */
    func cancel() {
        worker?.cancel()
        worker = nil
        progress = nil
        active = [:]
        try? graph.library.db?.clearQueuedDownloads()
        refreshCounts()
    }

    /** Take tracks out of the queue before they are fetched. */
    func dequeue(_ songIds: [String]) async {
        guard let db = graph.library.db else { return }
        let queued = db.downloads(songIds).filter { $0.state != DownloadState.done }.map { $0.songId }
        if !queued.isEmpty { try? db.deleteDownloads(queued) }
        refreshCounts()
    }

    func retryFailed() async -> Int {
        guard let db = graph.library.db else { return 0 }
        let count = (try? db.requeueFailed(now: Format.nowMs())) ?? 0
        refreshCounts()
        if count > 0 { startWorker() }
        return count
    }

    func clearFailed() async {
        try? graph.library.db?.clearFailedDownloads()
    }

    func queuedRows(_ limit: Int) -> [DownloadRow] {
        graph.library.db?.queuedDownloads(limit) ?? []
    }

    func failedRows() -> [DownloadRow] {
        graph.library.db?.failedDownloads() ?? []
    }

    func usage() -> DownloadUsage {
        graph.library.db?.downloadUsage() ?? DownloadUsage(count: 0, bytes: 0)
    }

    @discardableResult
    func remove(_ songIds: [String]) async -> Int {
        guard let db = graph.library.db, let directory else { return 0 }
        let rows = db.downloads(songIds)
        for row in rows {
            if let path = row.path { try? FileManager.default.removeItem(at: directory.appendingPathComponent(path)) }
            paths[row.songId] = nil
        }
        try? db.deleteDownloads(songIds)
        reload()
        return rows.count
    }

    func removeAll() async -> Int {
        guard let db = graph.library.db, let directory else { return 0 }
        cancel()
        let all = db.doneDownloads()
        for row in all {
            if let path = row.path { try? FileManager.default.removeItem(at: directory.appendingPathComponent(path)) }
        }
        try? db.deleteDownloads(all.map { $0.songId })
        try? db.clearFailedDownloads()
        reload()
        return all.count
    }
}

/**
 * iPhones cannot play Opus or Vorbis through AVFoundation, so those (and
 * "server default", which Navidrome turns into Opus) become MP3 here.
 */
func playableFormat(_ preferred: String) -> String {
    switch preferred.lowercased() {
    case "aac": return "aac"
    default: return "mp3"
    }
}
