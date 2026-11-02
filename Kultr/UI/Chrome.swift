import SwiftUI
import UIKit

/**
 * The app once signed in: a tab per section, each with its own navigation
 * stack, in the system's liquid glass tab bar (with the round search button
 * beside it and the mini player as its accessory), and the full player as a
 * sheet over everything.
 */
struct MainUI: View {
    @Environment(\.kultr) private var theme

    var body: some View {
        @Bindable var ui = AppGraph.shared.ui
        let graph = AppGraph.shared
        let playerOpen = ui.playerOpen && graph.player.state.current != nil
        ZStack(alignment: .top) {
            SystemTabs()

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

            ToastLayer().zIndex(5)
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
        .task {
            graph.updates.checkInBackground()
            // A moment after opening, so it slides up over the app rather than with it.
            try? await Task.sleep(nanoseconds: 600_000_000)
            ui.checkWhatsNew()
        }
        .animation(theme.ease, value: graph.updates.available?.version)
        .sheet(item: $ui.update) { release in
            UpdateScreen(release: release)
                .environment(\.kultr, theme)
        }
        .sheet(isPresented: $ui.whatsNew, onDismiss: { ui.finishWhatsNew() }) {
            WhatsNewScreen { ui.finishWhatsNew() }
                .environment(\.kultr, theme)
        }
        .modifier(Dialogs(active: !playerOpen))
        // A sheet, so pulling it down is iOS's own gesture and runs at full frame rate.
        .sheet(isPresented: Binding(get: { playerOpen }, set: { ui.playerOpen = $0 })) {
            NowPlayingScreen()
                .overlay(alignment: .top) { ToastLayer() }
                .animation(theme.ease, value: graph.messages.current)
                // While the player is up, dialogs open over it rather than behind it.
                .modifier(Dialogs(active: true))
                .presentationDragIndicator(.visible)
                .presentationBackground {
                    if theme.settings.backdropArtwork {
                        ArtworkBackdrop(coverId: graph.player.state.current?.artworkId)
                    } else {
                        theme.colors.background
                    }
                }
                // Last, so the backdrop and the dialogs get the theme too.
                .environment(\.kultr, theme)
        }
    }
}

/** The note at the top that says what just happened. */
private struct ToastLayer: View {
    var body: some View {
        if let message = AppGraph.shared.messages.current {
            ToastView(message: message)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(message.id)
        }
    }
}

/**
 * Add to playlist, rating and the sleep timer. A sheet can only open from
 * the topmost screen, so these hang off the player while it is up and off
 * the app otherwise; [active] says which one.
 */
private struct Dialogs: ViewModifier {
    @Environment(\.kultr) private var theme
    let active: Bool

    func body(content: Content) -> some View {
        let ui = AppGraph.shared.ui
        content
            .sheet(isPresented: Binding(get: { active && ui.addToPlaylist != nil }, set: { if !$0 { ui.addToPlaylist = nil } })) {
                AddToPlaylistSheet(songs: ui.addToPlaylist ?? []) { ui.addToPlaylist = nil }
                    .environment(\.kultr, theme)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.regularMaterial)
            }
            .sheet(isPresented: Binding(get: { active && ui.rate != nil }, set: { if !$0 { ui.rate = nil } })) {
                if let song = ui.rate {
                    RatingSheet(song: song) { ui.rate = nil }
                        .environment(\.kultr, theme)
                        .presentationDetents([.height(240)])
                        .presentationBackground(.regularMaterial)
                }
            }
            .sheet(isPresented: Binding(get: { active && ui.sleepTimer }, set: { ui.sleepTimer = $0 })) {
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
        NavigationStack(path: Binding(get: { ui.paths[tab] ?? [] }, set: { ui.paths[tab] = $0 })) {
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
                    .padding(.bottom, 8)
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
        case .library: LibraryHome()
        case .search: SearchScreen()
        case .settings: SettingsScreen()
        }
    }
}

private struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .library(let tab): LibraryScreen(tab: tab)
        case .album(let id): AlbumScreen(id: id)
        case .artist(let id): ArtistScreen(id: id)
        case .playlist(let id): PlaylistScreen(id: id)
        case .genre(let name): GenreScreen(name: name)
        case .sync: SyncScreen()
        case .stats: StatsScreen()
        case .recap: RecapScreen()
        case .downloads(let page): DownloadsScreen(initialPage: page)
        }
    }
}
