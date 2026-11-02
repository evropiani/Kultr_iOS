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

    private static func open(_ screen: String, _ graph: AppGraph) async {
        let actions = graph.actions
        let library = graph.library
        switch screen {
        case "library": actions.selectTab(.library)
        case "albums":
            actions.selectTab(.library)
            actions.openLibrary(.albums)
        case "songs":
            actions.selectTab(.home)
            actions.openLibrary(.songs)
        case "search": actions.selectTab(.search)
        case "found":
            // Search with something typed: the field in the bar, results above it.
            actions.selectTab(.search)
            graph.ui.searchQuery = "love"
        case "settings": actions.selectTab(.settings)
        case "stats": actions.navigate(.stats)
        case "recap":
            await seedListening()
            actions.navigate(.recap)
        case "whatsnew": graph.ui.whatsNew = true
        case "stations": actions.navigate(.stations)
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
        case "widget-large":
            // The large and extra-large faces, with the album's other songs up next.
            if let album = await library.recentlyAdded(3).last {
                actions.play(await library.songsOfAlbumNow(album.id))
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
            ScreenshotState.shared.showLargeWidgets = true
        case "player", "mini":
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

    /**
     * Made-up plays on this phone, this month and last, so the recap has
     * something to show. Marked as sent, so none of it reaches the demo server.
     */
    private static func seedListening() async {
        let library = AppGraph.shared.library
        guard let db = library.db, db.recentHistory(1).isEmpty else { return }
        let songs = await library.randomSongs(30)
        let calendar = Calendar.current
        let now = Format.nowMs()
        guard let start = calendar.dateInterval(of: .month, for: Date())?.start else { return }
        let monthStart = Int64(start.timeIntervalSince1970 * 1000)
        let span = max(3_600_000, now - monthStart - 60_000)
        var plays: [(String, Int, Int64)] = []
        for (rank, song) in songs.enumerated() {
            for _ in 0..<max(1, 6 - rank / 4) { plays.append((song.id, song.duration ?? 200, 0)) }
        }
        for (i, play) in plays.enumerated() {
            let at = monthStart + span * Int64(i) / Int64(max(1, plays.count))
            _ = try? db.insertHistory(HistoryEntry(songId: play.0, playedAt: at, seconds: play.1, completed: true, source: "screenshot", submitted: true))
        }
        for (i, song) in songs.prefix(12).enumerated() {
            let at = monthStart - Int64(i + 1) * 86_400_000
            _ = try? db.insertHistory(HistoryEntry(songId: song.id, playedAt: at, seconds: song.duration ?? 200, completed: true, source: "screenshot", submitted: true))
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
    var showLargeWidgets = false
}

/** The large widget as an iPhone shows it, and the extra-large one as an iPad would, scaled to fit. */
struct LargeWidgetPreviewScreen: View {
    var body: some View {
        let bridge = WidgetBridge.shared
        ZStack {
            Color(red: 0.16, green: 0.14, blue: 0.12)
                .ignoresSafeArea()
            VStack(spacing: 26) {
                face(.systemLarge, CGSize(width: 364, height: 382), bridge)
                face(.systemExtraLarge, CGSize(width: 715, height: 354), bridge)
                    .scaleEffect(364 / 715)
                    .frame(width: 364, height: 354 * 364 / 715)
            }
            .padding(.top, 30)
        }
    }

    private func face(_ family: WidgetFamily, _ size: CGSize, _ bridge: WidgetBridge) -> some View {
        NowPlayingWidgetView(family: family, snapshot: bridge.snapshot, artwork: bridge.artwork, queueArtwork: bridge.queueArtwork)
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background { NowPlayingWidgetBackground() }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
    }
}

/** The widget's faces as the home screen and lock screen would show them, for CI's screenshots. */
struct WidgetPreviewScreen: View {
    var body: some View {
        let bridge = WidgetBridge.shared
        ZStack {
            Color(red: 0.16, green: 0.14, blue: 0.12)
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
            .background { NowPlayingWidgetBackground() }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
    }
}
#endif
