import Foundation

/**
 * The app's object graph. Built once and reached through [AppGraph.shared]
 * from the player, background tasks and the interface.
 */
@MainActor
final class AppGraph {
    static let shared = AppGraph()

    let settings = SettingsStore()
    let messages = UiMessages()
    let network = NetworkMonitor()
    let auth = AuthRepository()
    let ui = AppUI()
    private(set) var library: LibraryRepository!
    private(set) var scrobbles: Scrobbles!
    private(set) var sync: SyncManager!
    private(set) var offline: OfflineManager!
    private(set) var analysis: AnalysisManager!
    private(set) var player: PlayerController!
    private(set) var actions: AppActions!

    private init() {
        library = LibraryRepository(graph: self)
        scrobbles = Scrobbles(graph: self)
        sync = SyncManager(graph: self)
        offline = OfflineManager(graph: self)
        analysis = AnalysisManager(graph: self)
        player = PlayerController(graph: self)
        actions = AppActions(graph: self)

        library.activate(auth.active?.id)
        auth.observeActive { [unowned self] profile in
            self.library.activate(profile?.id)
            self.offline.reload()
            self.ui.path = []
        }
        offline.start()
        player.start()
        sync.onAppStart()
    }

    /** Close and delete everything stored for a server that has been forgotten. */
    func deleteDataFor(_ profileId: String) {
        library.deleteDataFor(profileId)
        offline.deleteDataFor(profileId)
    }

    func clearMediaCache() {
        StreamCache.shared.clear()
    }
}
