import SwiftUI
import UIKit

/**
 * The root of the interface: the theme (tinted by what is playing), then the
 * sign-in screen without a server, or the tabs, the mini player and the
 * full-screen player on top.
 */
struct RootView: View {
    @Environment(\.colorScheme) private var systemScheme
    @State private var accent: UInt32 = 0x7C8CFF

    var body: some View {
        let settings = AppGraph.shared.settings.settings
        let dark: Bool = {
            switch settings.theme {
            case .dark: return true
            case .light: return false
            case .system: return systemScheme == .dark
            }
        }()
        let theme = KultrTheme(
            colors: .make(dark: dark, accent: accent, settings: settings),
            radii: .of(settings.corners),
            settings: settings
        )
        let coverId = AppGraph.shared.player.state.current?.artworkId
        AppContent()
            .environment(\.kultr, theme)
            .preferredColorScheme(settings.theme == .system ? nil : (dark ? .dark : .light))
            .tint(theme.colors.accent)
            .task(id: AccentKey(coverId: coverId, mode: settings.accentMode, accent: settings.accent, blend: settings.accentBlend)) {
                let next = await Self.resolveAccent(coverId: coverId, settings: settings)
                withAnimation(.easeInOut(duration: settings.reduceMotion ? 0 : 0.9)) { accent = next }
            }
    }

    private struct AccentKey: Hashable {
        let coverId: String?
        let mode: AccentMode
        let accent: String
        let blend: Int
    }

    /**
     * The accent the whole interface is tinted with: taken from the artwork of
     * what is playing (optionally blended with the chosen colour), or fixed.
     */
    @MainActor
    private static func resolveAccent(coverId: String?, settings: Settings) async -> UInt32 {
        let chosen = ArtworkColor.parseHex(settings.accent) ?? 0xFF7C_8CFF
        guard settings.accentMode == .artwork, let url = artworkUrl(coverId, 96),
              let sampled = await ImageLoader.shared.dominantColor(url)
        else { return chosen }
        let blend = min(100, max(0, settings.accentBlend))
        return blend == 0 ? sampled : ArtworkColor.mix(sampled, chosen, Double(blend) / 100)
    }
}

private struct AppContent: View {
    var body: some View {
        let auth = AppGraph.shared.auth
        let ui = AppGraph.shared.ui
        if let profile = auth.active {
            if auth.client == nil {
                LoginScreen(prefillUrl: profile.serverUrl, prefillUser: profile.username, onCancel: { auth.signOut() })
            } else {
                ZStack {
                    MainUI()
                    if let request = ui.login {
                        LoginScreen(
                            prefillUrl: request.url,
                            prefillUser: request.user,
                            onCancel: { ui.login = nil },
                            onDone: { ui.login = nil }
                        )
                        .transition(.move(edge: .bottom))
                        .zIndex(10)
                    }
                }
            }
        } else {
            LoginScreen()
        }
    }
}

private struct MainUI: View {
    @Environment(\.kultr) private var theme
    @State private var keyboardOpen = false

    var body: some View {
        @Bindable var ui = AppGraph.shared.ui
        let graph = AppGraph.shared
        let player = graph.player.state
        let onDownloads = ui.onDownloadsPage
        ZStack(alignment: .bottom) {
            AppBackdrop()
            VStack(spacing: 0) {
                NavigationStack(path: $ui.path) {
                    TabRoot(tab: ui.tab)
                        .navigationDestination(for: Route.self) { route in
                            RouteView(route: route)
                        }
                }
                .frame(maxHeight: .infinity)
                if !keyboardOpen {
                    if !onDownloads { DownloadIndicator() }
                    MiniPlayer()
                    BottomBar()
                }
            }

            if let message = graph.messages.current {
                ToastView(message: message)
                    .padding(.bottom, keyboardOpen ? 8 : (player.current != nil ? 150 : 90) + (graph.offline.status != .idle ? 48 : 0))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(5)
                    .id(message.id)
            }

            if ui.playerOpen && player.current != nil {
                NowPlayingScreen()
                    .transition(.move(edge: .bottom))
                    .zIndex(20)
            }

            DropZoneOverlay()
                .zIndex(30)
        }
        .animation(.easeOut(duration: 0.25), value: graph.messages.current)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardOpen = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardOpen = false }
        .sheet(isPresented: Binding(get: { ui.addToPlaylist != nil }, set: { if !$0 { ui.addToPlaylist = nil } })) {
            AddToPlaylistSheet(songs: ui.addToPlaylist ?? []) { ui.addToPlaylist = nil }
                .environment(\.kultr, theme)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: Binding(get: { ui.rate != nil }, set: { if !$0 { ui.rate = nil } })) {
            if let song = ui.rate {
                RatingSheet(song: song) { ui.rate = nil }
                    .environment(\.kultr, theme)
                    .presentationDetents([.height(240)])
            }
        }
        .sheet(isPresented: $ui.sleepTimer) {
            SleepTimerSheet { ui.sleepTimer = false }
                .environment(\.kultr, theme)
                .presentationDetents([.medium, .large])
        }
    }
}

/** The start page of each tab. */
private struct TabRoot: View {
    let tab: MainTab

    var body: some View {
        switch tab {
        case .home: HomeScreen()
        case .library: LibraryScreen(initialTab: .albums)
        case .search: SearchScreen()
        case .settings: SettingsScreen()
        }
    }
}

private struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .library(let tab): LibraryScreen(initialTab: tab)
        case .album(let id): AlbumScreen(id: id)
        case .artist(let id): ArtistScreen(id: id)
        case .playlist(let id): PlaylistScreen(id: id)
        case .genre(let name): GenreScreen(name: name)
        case .sync: SyncScreen()
        case .stats: StatsScreen()
        case .downloads(let page): DownloadsScreen(initialPage: page)
        }
    }
}

private struct BottomBar: View {
    @Environment(\.kultr) private var theme

    var body: some View {
        let ui = AppGraph.shared.ui
        let selected = ui.highlightedTab
        let c = theme.colors
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                let isOn = tab == selected
                Button {
                    AppGraph.shared.actions.selectTab(tab)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(isOn ? c.accent : c.ink3)
                            .frame(width: 64, height: 32)
                            .background(Capsule().fill(isOn ? c.accentSoft : .clear))
                        Text(tab.label)
                            .font(KFont.labelMedium)
                            .foregroundStyle(isOn ? c.ink : c.ink3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(tab.label)
            }
        }
        .background(c.elevated.opacity(0.92).ignoresSafeArea(edges: .bottom))
    }
}
