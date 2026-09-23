import BackgroundTasks
import Foundation
import Observation

/** Runs library syncs and remembers how the last one went, for the Sync page. */
@MainActor
@Observable
final class SyncManager {
    static let refreshTaskId = "app.kultr.ios.sync"

    private(set) var running = false
    private(set) var progress: SyncProgress?
    private(set) var summary: SyncSummary?
    private(set) var error: String?

    @ObservationIgnored private unowned let graph: AppGraph
    @ObservationIgnored private var task: Task<Void, Never>?

    init(graph: AppGraph) {
        self.graph = graph
    }

    /** Start a sync unless one is already running. */
    func start(_ mode: SyncMode, quiet: Bool = false) {
        if running {
            if !quiet { graph.messages.show("A sync is already running.") }
            return
        }
        task = Task { [weak self] in
            _ = await self?.runNow(mode, quiet: quiet)
        }
    }

    func cancel() {
        task?.cancel()
    }

    /** Right after signing in to a server whose library is not on this phone yet, build it. */
    func startFirstSyncIfNeeded() {
        Task {
            let state = await graph.library.syncState()
            if state.lastCheck == nil { start(.full) }
        }
    }

    /** Run a sync and wait for it. Returns nil on success, or an error message. */
    @discardableResult
    func runNow(_ mode: SyncMode, quiet: Bool = false) async -> String? {
        guard let client = graph.auth.client, let db = graph.library.db else { return "Not signed in." }
        if running { return nil }
        running = true
        error = nil
        defer { running = false }
        let includePlaylists = graph.settings.current.syncPlaylistContents
        let report: (SyncProgress) -> Void = { [weak self] progress in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.progress = progress }
            }
        }
        let work = Task.detached(priority: .utility) { () -> SyncSummary in
            try await LibrarySync(client: client, store: DatabaseLibraryStore(db)).run(
                mode: mode,
                includePlaylistContents: includePlaylists,
                onProgress: report
            )
        }
        do {
            let summary = try await withTaskCancellationHandler {
                try await work.value
            } onCancel: {
                work.cancel()
            }
            self.summary = summary
            if !quiet {
                if summary.upToDate {
                    graph.messages.success("Everything is up to date.")
                } else if summary.mode == .full {
                    graph.messages.success("Library synced: \(summary.counts.songs) tracks in \(summary.counts.albums) albums.")
                } else {
                    graph.messages.success("Updated: \(summary.albumsAdded) new, \(summary.albumsUpdated) changed, \(summary.albumsRemoved) removed.")
                }
            }
            await graph.scrobbles.flush()
            return nil
        } catch is CancellationError {
            if !quiet { graph.messages.show("Sync cancelled.") }
            return nil
        } catch {
            let message = describeError(error)
            self.error = message
            if !quiet { graph.messages.error("Sync failed: \(message)") }
            return message
        }
    }

    /**
     * On startup: if the library has been synced before and the server looks
     * different, pull in the changes. A never-synced library waits for the
     * person to press the button, since the first sync is the expensive one.
     */
    func onAppStart() {
        scheduleBackgroundCheck()
        guard graph.settings.current.autoSyncOnStart else { return }
        Task {
            _ = await quickCheckAndSync()
        }
    }

    /** The cheap "anything new?" probe, followed by a delta sync when it says so. */
    func quickCheckAndSync() async -> Bool {
        guard let client = graph.auth.client, let db = graph.library.db else { return false }
        let state = await graph.library.syncState()
        if state.lastCheck == nil { return false }
        let check = try? await Task.detached(priority: .utility) {
            try await LibrarySync(client: client, store: DatabaseLibraryStore(db)).quickCheck()
        }.value
        if check?.changed == true { await runNow(.check, quiet: true) }
        await graph.scrobbles.flush()
        return true
    }

    // ---------------------------------------------------------- background --

    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskId, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                AppGraph.shared.sync.handleBackgroundRefresh(refresh)
            }
        }
    }

    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        scheduleBackgroundCheck()
        let work = Task { [weak self] in
            _ = await self?.quickCheckAndSync()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    /** Ask iOS to wake Kultr every so often to look for changes on the server. */
    func scheduleBackgroundCheck() {
        let minutes = graph.settings.current.autoSyncMinutes
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskId)
        guard minutes > 0 else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Double(max(15, minutes)) * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
