#if DEBUG
import Foundation

/**
 * For CI's simulator screenshots only (Debug builds). With KULTR_DEMO_SERVER
 * set in the environment, Kultr signs in to that server, syncs it once, opens
 * the screen named by KULTR_SCREEN and then drops a marker file in Documents
 * so the script knows when to take the picture. Release builds leave this out.
 */
@MainActor
enum ScreenshotDriver {
    static func start() {
        let env = ProcessInfo.processInfo.environment
        guard let server = env["KULTR_DEMO_SERVER"], !server.isEmpty else { return }
        let screen = env["KULTR_SCREEN"] ?? "home"
        Task { @MainActor in
            let graph = AppGraph.shared
            if screen == "login" {
                // The very first launch: nothing signed in yet.
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                mark(screen, "ok")
                return
            }
            if graph.auth.client == nil {
                let input = AuthRepository.LoginInput(
                    serverUrl: server,
                    username: env["KULTR_DEMO_USER"] ?? "demo",
                    password: env["KULTR_DEMO_PASS"] ?? "demo",
                    label: "Navidrome demo",
                    authMode: .token
                )
                if let error = await graph.auth.login(input) {
                    mark(screen, "login failed: \(error)")
                    return
                }
            }
            if await graph.library.syncState().lastCheck == nil {
                _ = await graph.sync.runNow(.full, quiet: true)
            }
            await open(screen, graph)
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            mark(screen, "ok")
        }
    }

    private static func open(_ screen: String, _ graph: AppGraph) async {
        let actions = graph.actions
        let library = graph.library
        switch screen {
        case "library": actions.selectTab(.library)
        case "songs":
            actions.selectTab(.home)
            actions.openLibrary(.songs)
        case "search": actions.selectTab(.search)
        case "settings": actions.selectTab(.settings)
        case "stats": actions.navigate(.stats)
        case "sync": actions.navigate(.sync)
        case "downloads": actions.openDownloads(.now)
        case "album":
            if let album = await library.recentlyAdded(1).first { actions.openAlbum(album.id) }
        case "artist":
            let artists = await library.artists()
            if let artist = artists.first(where: { ($0.albumCount ?? 0) > 1 }) ?? artists.first {
                actions.openArtist(artist.id)
            }
        case "player", "mini":
            if let album = await library.recentlyAdded(3).last {
                let songs = await library.songsOfAlbumNow(album.id)
                actions.play(songs)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if screen == "player" { actions.openPlayer() }
            }
        default:
            actions.selectTab(.home)
        }
    }

    private static func mark(_ screen: String, _ note: String) {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? note.write(to: documents.appendingPathComponent("kultr-ready-\(screen)"), atomically: true, encoding: .utf8)
    }
}
#endif
