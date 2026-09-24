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
                        .background { PlainBackdrop() }
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
