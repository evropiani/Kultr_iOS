import SwiftUI
import UIKit

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
 * Kultr's palette: cream pages and warm black text in light mode, warm
 * charcoal in dark, and one orange for whatever you can tap. Colour is flat
 * everywhere; the album cover is the only colourful thing on screen. With
 * "Colour from artwork" on, the accent comes from what is playing instead.
 */
struct KultrColors: Equatable {
    var dark: Bool
    /** Night mode: dark, on pure black, with less light behind the content. */
    var night = false
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
    /** The fill of a tinted button, like Apple Music's Play and Shuffle. */
    var sand: Color { dark ? ink.opacity(0.1) : Color(argb: 0xEADFCC) }

    static func make(dark: Bool, accent picked: UInt32, settings: Settings) -> KultrColors {
        // A pale colour washes out on cream, so in light mode it is darkened
        // until it reads as text there.
        let argb = dark ? picked : readableOnLight(picked)
        let accent = Color(argb: argb)
        let scale = Double(min(200, max(0, settings.surfaceOpacity))) / 100
        let inkBase = Color(argb: dark ? 0xF3EDE2 : 0x1F1A14)
        let edgeBase: Color = settings.surfaceBorder == .accent ? accent : inkBase
        let edgeAlpha = Double(min(100, max(0, settings.borderOpacity))) / 100 * (dark ? 0.5 : 0.35)
        // Whichever of white and ink reads better on the accent.
        let onAccent: Color = ArtworkColor.luminance(argb) > 0.2 ? Color(argb: 0x1F1A14) : .white
        if dark {
            // Night mode is for OLED screens: black pixels are switched off, so
            // the background is true black and raised surfaces only just lift.
            let night = settings.nightMode
            return KultrColors(
                dark: true,
                night: night,
                accent: accent,
                onAccent: onAccent,
                background: Color(argb: night ? 0x000000 : 0x1C1A17),
                elevated: Color(argb: night ? 0x0E0D0B : 0x26231F),
                ink: inkBase,
                ink2: inkBase.opacity(0.7),
                ink3: inkBase.opacity(0.5),
                ink4: inkBase.opacity(0.26),
                glass: inkBase.opacity(min(1, 0.07 * scale)),
                glassStrong: inkBase.opacity(min(1, 0.12 * scale)),
                edge: edgeBase.opacity(edgeAlpha),
                line: inkBase.opacity(0.1)
            )
        }
        let paper = Color(argb: 0xFFFCF6)
        return KultrColors(
            dark: false,
            accent: accent,
            onAccent: onAccent,
            background: Color(argb: 0xF6F0E5),
            elevated: paper,
            ink: inkBase,
            ink2: Color(argb: 0x5A5046),
            ink3: Color(argb: 0x6E6255),
            ink4: Color(argb: 0xA89C8D),
            glass: paper.opacity(min(1, 0.8 * scale)),
            glassStrong: paper,
            edge: edgeBase.opacity(edgeAlpha),
            line: inkBase.opacity(0.12)
        )
    }
}

extension KultrColors {
    /**
     * The colour darkened until its luminance is at most 0.15, so it reads as
     * text on cream (4.5:1). Hue stays, and pale colours gain a little
     * saturation so they turn deeper rather than grey.
     */
    static func readableOnLight(_ argb: UInt32) -> UInt32 {
        let target = 0.15
        guard ArtworkColor.luminance(argb) > target else { return argb }
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        UIColor(
            red: CGFloat((argb >> 16) & 0xff) / 255,
            green: CGFloat((argb >> 8) & 0xff) / 255,
            blue: CGFloat(argb & 0xff) / 255,
            alpha: 1
        ).getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        if s > 0.05 { s = min(1, max(s, 0.45) * 1.1) }
        var color = argb
        while v > 0.3 {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
            UIColor(hue: h, saturation: s, brightness: v, alpha: 1).getRed(&r, green: &g, blue: &b, alpha: &a)
            color = (UInt32(r * 255) << 16) | (UInt32(g * 255) << 8) | UInt32(b * 255)
            if ArtworkColor.luminance(color) <= target { break }
            v -= 0.02
        }
        return color
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
        colors: .make(dark: true, accent: 0xFF7A3D, settings: Settings()),
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

/**
 * The type scale, on iOS's own text styles, so every size follows Larger
 * Text in the iPhone's settings.
 */
enum KFont {
    static let headlineLarge = Font.largeTitle.bold()
    static let headlineSmall = Font.title2.bold()
    static let titleLarge = Font.title2.bold()
    static let titleMedium = Font.headline
    static let titleSmall = Font.subheadline.weight(.medium)
    static let bodyLarge = Font.body
    static let bodyMedium = Font.subheadline
    static let bodySmall = Font.footnote
    static let labelLarge = Font.subheadline.weight(.semibold)
    static let labelMedium = Font.footnote.weight(.medium)
    static let labelSmall = Font.caption.weight(.medium)
    /** A small label above a heading. */
    static let eyebrow = Font.caption.weight(.semibold)
}

extension View {
    /** The shared object graph, for any screen that needs it. */
    var graph: AppGraph { AppGraph.shared }
}
