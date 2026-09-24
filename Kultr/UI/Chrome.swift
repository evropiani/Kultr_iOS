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
            Group {
                if #available(iOS 26.0, *) {
                    SystemTabs()
                } else {
                    FloatingTabs()
                }
            }
            .allowsHitTesting(!playerOpen)
            .accessibilityHidden(playerOpen)

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
        }
        .animation(theme.ease, value: graph.messages.current)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Plays go up and plays from other devices come down whenever Kultr comes to the front.
            graph.sync.refreshListening()
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

// ------------------------------------------------------------ iOS 26 tabs --

@available(iOS 26.0, *)
private struct SystemTabs: View {
    @Environment(\.kultr) private var theme

    var body: some View {
        let graph = AppGraph.shared
        let ui = graph.ui
        let selection = Binding<MainTab>(get: { ui.tab }, set: { graph.actions.selectTab($0) })
        TabView(selection: selection) {
            Tab(MainTab.home.label, systemImage: MainTab.home.icon, value: MainTab.home) { TabStack(tab: .home) }
            Tab(MainTab.library.label, systemImage: MainTab.library.icon, value: MainTab.library) { TabStack(tab: .library) }
            Tab(MainTab.settings.label, systemImage: MainTab.settings.icon, value: MainTab.settings) { TabStack(tab: .settings) }
            Tab(MainTab.search.label, systemImage: MainTab.search.icon, value: MainTab.search, role: .search) { TabStack(tab: .search) }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .modifier(PlayerAccessory(enabled: graph.player.state.current != nil))
        .tint(theme.colors.accent)
    }
}

/** The mini player, riding on the tab bar as its accessory. */
@available(iOS 26.0, *)
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

@available(iOS 26.0, *)
private struct AccessoryPlayer: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        // Inline: the tab bar has shrunk while scrolling and the player sits beside it.
        MiniPlayerContent(compact: placement == .inline)
    }
}

// ------------------------------------------------------- floating tab bar --

/** Before iOS 26: every tab's stack kept alive, with Kultr's own glass bar floating over them. */
private struct FloatingTabs: View {
    @State private var keyboardOpen = false

    var body: some View {
        let ui = AppGraph.shared.ui
        ZStack {
            ForEach(MainTab.allCases, id: \.self) { tab in
                let shown = ui.tab == tab
                TabStack(tab: tab)
                    .opacity(shown ? 1 : 0)
                    .allowsHitTesting(shown)
                    .accessibilityHidden(!shown)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardOpen { FloatingChrome() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardOpen = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardOpen = false }
    }
}

private struct FloatingChrome: View {
    @Environment(\.kultr) private var theme

    var body: some View {
        let graph = AppGraph.shared
        let playing = graph.player.state.current != nil
        VStack(spacing: 8) {
            if !graph.ui.onDownloadsPage { DownloadIndicator(floating: true) }
            if playing {
                MiniPlayerContent(compact: false)
                    .frame(height: 56)
                    .kultrGlass(Capsule(), interactive: true)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 10) {
                LensTabBar()
                SearchOrb()
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 2)
        .animation(theme.spring, value: playing)
    }
}

/**
 * The tabs as one piece of glass. Touch it and the highlight lifts into a
 * clear lens that follows your finger, magnifying the tabs it passes; let go
 * and it settles on the tab underneath. A plain tap works as usual.
 */
private struct LensTabBar: View {
    @Environment(\.kultr) private var theme
    @State private var fingerX: CGFloat?
    @State private var lastSlot: Int?

    var body: some View {
        let ui = AppGraph.shared.ui
        let tabs = MainTab.bar
        let c = theme.colors
        GeometryReader { proxy in
            let width = proxy.size.width
            let slot = width / CGFloat(tabs.count)
            let selected = tabs.firstIndex(of: ui.tab)
            let lensWidth = slot - 6
            let center: CGFloat? = fingerX.map { min(max($0, slot / 2), width - slot / 2) }
                ?? selected.map { slot * (CGFloat($0) + 0.5) }
            let lifted = fingerX != nil
            ZStack(alignment: .leading) {
                if let center {
                    Capsule()
                        .fill(lifted ? Color.white.opacity(c.dark ? 0.1 : 0.35) : c.accentSoft)
                        .overlay(Capsule().strokeBorder(.white.opacity(lifted ? 0.45 : 0.12), lineWidth: lifted ? 1 : 0.5))
                        .shadow(color: .black.opacity(lifted ? 0.25 : 0), radius: 10, y: 4)
                        .frame(width: lensWidth, height: proxy.size.height - 8)
                        .scaleEffect(lifted && !theme.reduceMotion ? 1.14 : 1)
                        .offset(x: center - lensWidth / 2)
                }
                HStack(spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                        let mid = slot * (CGFloat(index) + 0.5)
                        let near = center.map { max(0, 1 - abs($0 - mid) / slot) } ?? 0
                        let magnify = lifted && !theme.reduceMotion ? 1 + 0.16 * near : 1
                        VStack(spacing: 3) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 18, weight: .semibold))
                            Text(tab.label)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(tab == ui.tab ? c.accent : c.ink)
                        .scaleEffect(magnify)
                        .frame(width: slot, height: proxy.size.height)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(tab == ui.tab ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { AppGraph.shared.actions.selectTab(tab) }
                    }
                }
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let index = min(tabs.count - 1, max(0, Int(value.location.x / slot)))
                        if lastSlot != index {
                            if lastSlot != nil { Haptics.select() }
                            lastSlot = index
                        }
                        withAnimation(theme.reduceMotion ? nil : .interactiveSpring(response: 0.28, dampingFraction: 0.78)) {
                            fingerX = value.location.x
                        }
                    }
                    .onEnded { value in
                        let index = min(tabs.count - 1, max(0, Int(value.location.x / slot)))
                        lastSlot = nil
                        if tabs[index] != ui.tab { Haptics.select() }
                        withAnimation(theme.spring) {
                            fingerX = nil
                            AppGraph.shared.actions.selectTab(tabs[index])
                        }
                    }
            )
        }
        .frame(height: 58)
        .kultrGlass(Capsule())
    }
}

private struct SearchOrb: View {
    @Environment(\.kultr) private var theme

    var body: some View {
        let ui = AppGraph.shared.ui
        let on = ui.tab == .search
        Button {
            Haptics.select()
            withAnimation(theme.spring) { AppGraph.shared.actions.selectTab(.search) }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(on ? theme.colors.accent : theme.colors.ink)
                .frame(width: 58, height: 58)
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .kultrGlass(Circle(), tint: on ? theme.colors.accent : nil)
        .accessibilityLabel("Search")
        .accessibilityAddTraits(on ? .isSelected : [])
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

/** On iOS 26 the download strip floats above the system tab bar, as one more piece of glass. */
private struct FloatingDownloads: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                if !AppGraph.shared.ui.onDownloadsPage {
                    DownloadIndicator(floating: true)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }
            }
        } else {
            content
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
