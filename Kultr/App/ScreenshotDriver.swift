#if DEBUG
import Foundation
import SwiftUI
import WidgetKit

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
            let look: ThemeMode = env["KULTR_LOOK"] == "light" ? .light : .dark
            if graph.settings.settings.theme != look { graph.settings.update { $0.theme = look } }
            if screen == "login" || screen == "welcome" {
                // The very first launch: nothing signed in yet, so the welcome.
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                mark(screen, "ok")
                return
            }
            graph.ui.finishWelcome()
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

    /** For the "lens" screenshot: a finger held on the tab bar, between Home and Library. */
    nonisolated static var lensFinger: CGFloat? {
        ProcessInfo.processInfo.environment["KULTR_SCREEN"] == "lens" ? 120 : nil
    }

    private static func open(_ screen: String, _ graph: AppGraph) async {
        let actions = graph.actions
        let library = graph.library
        switch screen {
        case "library", "library-switch": actions.selectTab(.library)
        case "songs":
            actions.selectTab(.home)
            actions.openLibrary(.songs)
        case "search": actions.selectTab(.search)
        case "lens": actions.selectTab(.home)
        case "found":
            // Search with something typed: the field in the bar, results above it.
            actions.selectTab(.search)
            graph.ui.searchQuery = "love"
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
        case "widget":
            // The widget's faces, drawn by the app, with what is playing.
            if let album = await library.recentlyAdded(3).last {
                actions.play(await library.songsOfAlbumNow(album.id))
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
            ScreenshotState.shared.showWidgets = true
        case "player", "mini", "pull":
            if let album = await library.recentlyAdded(3).last {
                let songs = await library.songsOfAlbumNow(album.id)
                actions.play(songs)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if screen != "mini" { actions.openPlayer() }
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


@MainActor
@Observable
final class ScreenshotState {
    static let shared = ScreenshotState()
    var showWidgets = false
}

/** The widget's faces as the home screen and lock screen would show them, for CI's screenshots. */
struct WidgetPreviewScreen: View {
    var body: some View {
        let bridge = WidgetBridge.shared
        ZStack {
            LinearGradient(colors: [Color(red: 0.24, green: 0.18, blue: 0.42), Color(red: 0.06, green: 0.08, blue: 0.16)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 22) {
                home(.systemMedium, width: 364, bridge)
                HStack(spacing: 24) {
                    home(.systemSmall, width: 170, bridge)
                    VStack(spacing: 14) {
                        NowPlayingWidgetView(family: .accessoryRectangular, snapshot: bridge.snapshot, artwork: nil)
                            .frame(width: 160, height: 72)
                        NowPlayingWidgetView(family: .accessoryCircular, snapshot: bridge.snapshot, artwork: nil)
                            .frame(width: 72, height: 72)
                    }
                    .foregroundStyle(.white)
                    .frame(width: 170)
                }
                home(.systemSmall, width: 170, nil)
            }
            .padding(.top, 40)
        }
    }

    private func home(_ family: WidgetFamily, width: CGFloat, _ bridge: WidgetBridge?) -> some View {
        NowPlayingWidgetView(family: family, snapshot: bridge?.snapshot, artwork: bridge?.artwork)
            .padding(14)
            .frame(width: width, height: 170)
            .background { NowPlayingWidgetBackground(snapshot: bridge?.snapshot, artwork: bridge?.artwork) }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
    }
}
#endif
