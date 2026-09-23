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
    // Lazy only so they can be handed `self`; all of them are created in init.
    private(set) lazy var library = LibraryRepository(graph: self)
    private(set) lazy var scrobbles = Scrobbles(graph: self)
    private(set) lazy var sync = SyncManager(graph: self)
    private(set) lazy var offline = OfflineManager(graph: self)
    private(set) lazy var analysis = AnalysisManager(graph: self)
    private(set) lazy var player = PlayerController(graph: self)
    private(set) lazy var actions = AppActions(graph: self)

    private init() {
        _ = (library, scrobbles, sync, offline, analysis, player, actions)

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
