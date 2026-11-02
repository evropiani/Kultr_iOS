import SwiftUI
import UIKit

/**
 * The app once signed in: a tab per section, each with its own navigation
 * stack, the mini player floating above the tab bar, and the full-screen
 * player over everything.
 *
 * On iOS 26 the tab bar is the system's own liquid glass bar (with the lens
 * that follows your finger, the round search button beside it, and the mini
 * player as its accessory). Before iOS 26, Kultr draws a floating glass bar
 * that behaves the same way.
 */
struct MainUI: View {
    @Environment(\.kultr) private var theme

    var body: some View {
        @Bindable var ui = AppGraph.shared.ui
        let graph = AppGraph.shared
        let playerOpen = ui.playerOpen && graph.player.state.current != nil
        ZStack(alignment: .top) {
            SystemTabs()
                .allowsHitTesting(!playerOpen)
                .accessibilityHidden(playerOpen)

            // A new version: a note at the top until it is opened or dismissed.
            if let release = graph.updates.available, release.version != graph.updates.dismissed,
               graph.messages.current == nil, !playerOpen, ui.tab != .search {
                UpdateBanner(
                    release: release,
                    onOpen: { ui.update = release },
                    onDismiss: { withAnimation(theme.ease) { graph.updates.dismiss(release) } }
                )
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(4)
            }

            if let message = graph.messages.current {
                ToastView(message: message)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(5)
                    .id(message.id)
            }

            if playerOpen {
                NowPlayingScreen()
                    .transition(.move(edge: .bottom))
                    .zIndex(20)
            }
            #if DEBUG
            if ScreenshotState.shared.showLargeWidgets {
                LargeWidgetPreviewScreen().zIndex(30)
            } else if ScreenshotState.shared.showWidgets {
                WidgetPreviewScreen().zIndex(30)
            }
            #endif
        }
        .animation(theme.ease, value: graph.messages.current)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Plays go up and plays from other devices come down whenever Kultr comes to the front.
            graph.sync.refreshListening()
            graph.updates.checkInBackground()
        }
        .task { graph.updates.checkInBackground() }
        .animation(theme.ease, value: graph.updates.available?.version)
        .sheet(item: Binding(get: { ui.update }, set: { ui.update = $0 })) { release in
            UpdateScreen(release: release)
                .environment(\.kultr, theme)
        }
        .sheet(isPresented: Binding(get: { ui.addToPlaylist != nil }, set: { if !$0 { ui.addToPlaylist = nil } })) {
            AddToPlaylistSheet(songs: ui.addToPlaylist ?? []) { ui.addToPlaylist = nil }
                .environment(\.kultr, theme)
                .presentationDetents([.medium, .large])
                .presentationBackground(.regularMaterial)
        }
        .sheet(isPresented: Binding(get: { ui.rate != nil }, set: { if !$0 { ui.rate = nil } })) {
            if let song = ui.rate {
                RatingSheet(song: song) { ui.rate = nil }
                    .environment(\.kultr, theme)
                    .presentationDetents([.height(240)])
                    .presentationBackground(.regularMaterial)
            }
        }
        .sheet(isPresented: $ui.sleepTimer) {
            SleepTimerSheet { ui.sleepTimer = false }
                .environment(\.kultr, theme)
                .presentationDetents([.medium, .large])
                .presentationBackground(.regularMaterial)
        }
    }
}

// ------------------------------------------------------------------ tabs --

private struct SystemTabs: View {
    @Environment(\.kultr) private var theme
    @FocusState private var searchFocused: Bool

    var body: some View {
        let graph = AppGraph.shared
        @Bindable var ui = graph.ui
        let selection = Binding<MainTab>(get: { ui.tab }, set: { graph.actions.selectTab($0) })
        TabView(selection: selection) {
            Tab(MainTab.home.label, systemImage: MainTab.home.icon, value: MainTab.home) { TabStack(tab: .home) }
            Tab(MainTab.library.label, systemImage: MainTab.library.icon, value: MainTab.library) { TabStack(tab: .library) }
            Tab(MainTab.settings.label, systemImage: MainTab.settings.icon, value: MainTab.settings) { TabStack(tab: .settings) }
            Tab(MainTab.search.label, systemImage: MainTab.search.icon, value: MainTab.search, role: .search) {
                // On the tab's stack rather than inside it: then the field lives in the
                // tab bar, growing out of the search button while the other tabs fold
                // into one, and rides up above the keyboard while you type.
                TabStack(tab: .search)
                    .searchable(text: $ui.searchQuery, prompt: "Artists, albums, tracks")
                    .searchFocused($searchFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .modifier(PlayerAccessory(enabled: graph.player.state.current != nil))
        .tint(theme.colors.accent)
        .onChange(of: ui.tab) { _, tab in
            // Choosing Search goes straight to typing, unless there is a search to come back to.
            guard tab == .search, ui.searchQuery.isEmpty else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                if AppGraph.shared.ui.tab == .search { searchFocused = true }
            }
        }
    }
}

/** The mini player, riding on the tab bar as its accessory. */
private struct PlayerAccessory: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: enabled) { AccessoryPlayer() }
        } else {
            content.tabViewBottomAccessory { AccessoryPlayer() }
        }
    }
}

private struct AccessoryPlayer: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        // Inline: the tab bar has shrunk while scrolling and the player sits beside it.
        MiniPlayerContent(compact: placement == .inline)
    }
}

// ------------------------------------------------------------ the stacks --

/** One tab: its start page and the pages opened from it. */
private struct TabStack: View {
    let tab: MainTab

    var body: some View {
        let ui = AppGraph.shared.ui
        NavigationStack(path: Binding(get: { ui.path(for: tab) }, set: { ui.setPath($0, for: tab) })) {
            TabRoot(tab: tab)
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .modifier(FloatingDownloads())
    }
}

/** The download strip floats above the tab bar, as one more piece of glass. */
private struct FloatingDownloads: ViewModifier {
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if !AppGraph.shared.ui.onDownloadsPage {
                DownloadIndicator(floating: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
        }
    }
}

/** The start page of each tab. */
private struct TabRoot: View {
    let tab: MainTab

    var body: some View {
        switch tab {
        case .home: HomeScreen()
        case .library: LibraryScreen(initialTab: .albums, isRoot: true)
        case .search: SearchScreen()
        case .settings: SettingsScreen()
        }
    }
}

private struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .library(let tab): LibraryScreen(initialTab: tab, isRoot: false)
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
