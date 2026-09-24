import SwiftUI
import UIKit

// Liquid glass on iOS 26 and later; a frosted material with a lit edge before.
// Glass is for the layer that floats over the content (tab bar, mini player,
// floating buttons), not for the content itself.

private struct GlassSurface<S: InsettableShape>: ViewModifier {
    @Environment(\.kultr) private var theme
    let shape: S
    var tint: Color?
    var interactive = false
    var shadow = true

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
            let dark = theme.colors.dark
            content
                .background(dark ? Material.ultraThinMaterial : Material.regularMaterial, in: shape)
                .background(shape.fill((tint ?? theme.colors.accent).opacity(tint == nil ? 0.05 : 0.18)))
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(dark ? 0.28 : 0.7), .white.opacity(dark ? 0.06 : 0.25)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
                )
                .shadow(color: .black.opacity(shadow ? (dark ? 0.35 : 0.14) : 0), radius: 18, y: 8)
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

extension View {
    /** A piece of glass in [shape]: liquid glass on iOS 26, frosted before. */
    func kultrGlass<S: InsettableShape>(_ shape: S, tint: Color? = nil, interactive: Bool = false, shadow: Bool = true) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, interactive: interactive, shadow: shadow))
    }
}

/**
 * Pieces of glass close together melt into each other on iOS 26 (and morph
 * when one appears or goes). Before iOS 26 this is just a stack.
 */
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/** A round glass button with an icon: the player's controls, floating actions. */
struct GlassIconButton: View {
    @Environment(\.kultr) private var theme
    let icon: String
    var size: CGFloat = 44
    var iconSize: CGFloat?
    var tint: Color?
    var prominent = false
    var label = ""
    let action: () -> Void

    var body: some View {
        let c = theme.colors
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: iconSize ?? size * 0.4, weight: .semibold))
                .foregroundStyle(prominent ? c.onAccent : (tint ?? c.ink))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .kultrGlass(Circle(), tint: prominent ? c.accent : nil, interactive: true, shadow: false)
        .accessibilityLabel(label)
    }
}

/** Shrinks a little while pressed, like the system's own controls. */
struct PressScaleStyle: ButtonStyle {
    @Environment(\.kultr) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !theme.reduceMotion ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(theme.reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/** Light taps of feedback, the way system controls give them. */
@MainActor
enum Haptics {
    private static let impact = UIImpactFeedbackGenerator(style: .light)
    private static let selection = UISelectionFeedbackGenerator()

    static func tap() { impact.impactOccurred(intensity: 0.6) }

    static func select() { selection.selectionChanged() }

    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

extension KultrTheme {
    /** Reduce motion, from Kultr's setting or the system's. */
    var reduceMotion: Bool { settings.reduceMotion || UIAccessibility.isReduceMotionEnabled }

    /** The spring used for moving highlights and rows, or none with Reduce motion. */
    var spring: Animation? { reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82) }

    /** A quick ease for things appearing and going. */
    var ease: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.22) }
}
