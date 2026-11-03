import SwiftUI
import UIKit

// Liquid glass, for the layer that floats over the content (tab bar, mini
// player, floating buttons), not for the content itself.

private struct GlassSurface<S: InsettableShape>: ViewModifier {
    @Environment(\.kultr) private var theme
    let shape: S
    var tint: Color?
    var interactive = false

    func body(content: Content) -> some View {
        // Kultr Studio's glass: frosted, or clear.
        var glass = theme.settings.clearGlass ? Glass.clear : Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return content.glassEffect(glass, in: shape)
    }
}

extension View {
    /** A piece of liquid glass in [shape]. */
    func kultrGlass<S: InsettableShape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, interactive: interactive))
    }
}

/** Pieces of glass close together melt into each other, and morph when one appears or goes. */
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) { content }
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
        .kultrGlass(Circle(), tint: prominent ? c.accent : nil, interactive: true)
        .accessibilityLabel(label.loc)
    }
}

/** A wide button (Play, Shuffle, Connect): orange when prominent, sand with an orange label otherwise. */
struct WideButton: View {
    @Environment(\.kultr) private var theme
    let title: String
    let icon: String
    let prominent: Bool
    var enabled = true
    let action: () -> Void

    var body: some View {
        let c = theme.colors
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button {
            Haptics.tap()
            action()
        } label: {
            Label(title.loc, systemImage: icon)
                .font(.headline)
                .foregroundStyle(prominent ? c.onAccent : c.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(shape.fill(prominent ? c.accent : c.sand))
                .opacity(enabled ? 1 : 0.5)
                .contentShape(shape)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
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
