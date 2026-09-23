import SwiftUI

extension Color {
    /** An opaque colour from packed 0xRRGGBB (or 0xAARRGGBB, alpha ignored). */
    init(argb: UInt32) {
        self.init(
            .sRGB,
            red: Double((argb >> 16) & 0xff) / 255,
            green: Double((argb >> 8) & 0xff) / 255,
            blue: Double(argb & 0xff) / 255,
            opacity: 1
        )
    }
}

/**
 * Kultr's palette is deliberately almost colourless. Colour arrives at
 * runtime: the accent is taken from the artwork of whatever is playing, and
 * every glass surface and border picks it up, so the interface takes on the
 * mood of the music.
 */
struct KultrColors: Equatable {
    var dark: Bool
    var accent: Color
    var onAccent: Color
    var background: Color
    var elevated: Color
    var ink: Color
    var ink2: Color
    var ink3: Color
    var ink4: Color
    var glass: Color
    var glassStrong: Color
    var edge: Color
    var line: Color
    var danger = Color(argb: 0xFF5F57)
    var warning = Color(argb: 0xFFBD2E)
    var success = Color(argb: 0x45D67A)

    var accentSoft: Color { accent.opacity(0.18) }
    var accentGlow: Color { accent.opacity(0.35) }

    static func make(dark: Bool, accent argb: UInt32, settings: Settings) -> KultrColors {
        let accent = Color(argb: argb)
        let scale = Double(min(200, max(0, settings.surfaceOpacity))) / 100
        let edgeBase: Color = settings.surfaceBorder == .accent ? accent : (dark ? .white : Color(argb: 0x0A0A10))
        let edgeAlpha = Double(min(100, max(0, settings.borderOpacity))) / 100 * (dark ? 0.8 : 0.6)
        let onAccent: Color = ArtworkColor.luminance(argb) > 0.45 ? Color(argb: 0x0A0A10) : .white
        let inkBase = Color(argb: 0x0A0A10)
        if dark {
            return KultrColors(
                dark: true,
                accent: accent,
                onAccent: onAccent,
                background: Color(argb: 0x08080C),
                elevated: Color(argb: 0x101018),
                ink: .white.opacity(0.96),
                ink2: .white.opacity(0.66),
                ink3: .white.opacity(0.42),
                ink4: .white.opacity(0.22),
                glass: .white.opacity(min(1, 0.07 * scale)),
                glassStrong: .white.opacity(min(1, 0.12 * scale)),
                edge: edgeBase.opacity(edgeAlpha),
                line: .white.opacity(0.09)
            )
        }
        return KultrColors(
            dark: false,
            accent: accent,
            onAccent: onAccent,
            background: Color(argb: 0xECEEF4),
            elevated: Color(argb: 0xF7F8FC),
            ink: inkBase.opacity(0.94),
            ink2: inkBase.opacity(0.62),
            ink3: inkBase.opacity(0.42),
            ink4: inkBase.opacity(0.2),
            glass: .white.opacity(min(1, 0.55 * scale)),
            glassStrong: .white.opacity(min(1, 0.72 * scale)),
            edge: edgeBase.opacity(edgeAlpha),
            line: inkBase.opacity(0.08)
        )
    }
}

struct KultrRadii: Equatable {
    var xs: CGFloat
    var sm: CGFloat
    var md: CGFloat
    var lg: CGFloat
    var xl: CGFloat

    static func of(_ style: CornerStyle) -> KultrRadii {
        switch style {
        case .sharp: return KultrRadii(xs: 3, sm: 4, md: 6, lg: 8, xl: 10)
        case .soft: return KultrRadii(xs: 8, sm: 12, md: 18, lg: 26, xl: 34)
        case .round: return KultrRadii(xs: 12, sm: 18, md: 26, lg: 34, xl: 44)
        }
    }
}

struct KultrTheme: Equatable {
    var colors: KultrColors
    var radii: KultrRadii
    var settings: Settings

    static let fallback = KultrTheme(
        colors: .make(dark: true, accent: 0x7C8CFF, settings: Settings()),
        radii: .of(.soft),
        settings: Settings()
    )
}

private struct KultrThemeKey: EnvironmentKey {
    static let defaultValue = KultrTheme.fallback
}

extension EnvironmentValues {
    var kultr: KultrTheme {
        get { self[KultrThemeKey.self] }
        set { self[KultrThemeKey.self] = newValue }
    }
}

/** Material 3's type scale, in SF Pro. */
enum KFont {
    static let headlineLarge = Font.system(size: 32, weight: .bold)
    static let headlineMedium = Font.system(size: 28, weight: .bold)
    static let headlineSmall = Font.system(size: 24, weight: .bold)
    static let titleLarge = Font.system(size: 22, weight: .bold)
    static let titleMedium = Font.system(size: 16, weight: .semibold)
    static let titleSmall = Font.system(size: 14, weight: .medium)
    static let bodyLarge = Font.system(size: 16)
    static let bodyMedium = Font.system(size: 14)
    static let bodySmall = Font.system(size: 12)
    static let labelLarge = Font.system(size: 14, weight: .semibold)
    static let labelMedium = Font.system(size: 12, weight: .medium)
    static let labelSmall = Font.system(size: 11, weight: .medium)
    /** Small caps-ish label used above headings ("ALBUM", "PLAYLIST"). */
    static let eyebrow = Font.system(size: 11, weight: .bold)
}

extension View {
    /** The shared object graph, for any screen that needs it. */
    var graph: AppGraph { AppGraph.shared }
}
