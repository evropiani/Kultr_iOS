import SwiftUI

extension Binding where Value == Bool {
    /** Shown while [item] holds something; dismissing clears it. For alerts and sheets about one thing. */
    init<Item>(isPresent item: Binding<Item?>) {
        self.init(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
    }
}

/** A button look that just dims while pressed, for custom-drawn controls. */
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/** A translucent panel with an accent-tinted edge — Kultr's "glass". */
struct GlassPanel<Content: View>: View {
    @Environment(\.kultr) private var theme
    var strong = false
    var padding: CGFloat = 16
    var radius: CGFloat?
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius ?? theme.radii.lg, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(strong ? theme.colors.glassStrong : theme.colors.glass))
            .overlay(shape.strokeBorder(theme.colors.edge, lineWidth: 1))
            .clipShape(shape)
    }
}

/** A capsule button: orange for the one action that leads, sand with an orange label otherwise. */
struct Pill: View {
    @Environment(\.kultr) private var theme
    let text: String
    var icon: String?
    var accent = false
    var enabled = true
    var badge: String?
    let action: () -> Void

    init(_ text: String, icon: String? = nil, accent: Bool = false, enabled: Bool = true, badge: String? = nil, action: @escaping () -> Void) {
        self.text = text
        self.icon = icon
        self.accent = accent
        self.enabled = enabled
        self.badge = badge
        self.action = action
    }

    var body: some View {
        let c = theme.colors
        let label = HStack(spacing: 7) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            Text(text)
                .font(KFont.labelLarge)
                .lineLimit(1)
            if let badge {
                Text(badge)
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(accent ? Color.white.opacity(0.22) : c.accentSoft))
            }
        }
        Button(action: tapped) {
            label
                .foregroundStyle(accent ? c.onAccent : c.accent)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(Capsule().fill(accent ? c.accent : c.sand))
                .opacity(enabled ? 1 : 0.45)
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
    }

    private func tapped() {
        Haptics.tap()
        action()
    }
}

/** A section's title, bold like Apple Music's, with room for an action on the right. */
struct SectionHeader<Action: View>: View {
    @Environment(\.kultr) private var theme
    let title: String
    @ViewBuilder var action: Action

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(theme.colors.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            action
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}

extension SectionHeader where Action == EmptyView {
    init(_ title: String) {
        self.title = title
        self.action = EmptyView()
    }
}

extension SectionHeader {
    init(_ title: String, @ViewBuilder action: () -> Action) {
        self.title = title
        self.action = action()
    }
}

struct Eyebrow: View {
    @Environment(\.kultr) private var theme
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(theme.colors.ink3)
            .lineLimit(1)
    }
}

struct EmptyState<Action: View>: View {
    @Environment(\.kultr) private var theme
    let icon: String
    let title: String
    var message: String?
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(theme.colors.accentSoft)
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(theme.colors.accent)
            }
            .frame(width: 64, height: 64)
            Text(title)
                .font(KFont.titleLarge)
                .foregroundStyle(theme.colors.ink)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(KFont.bodyMedium)
                    .foregroundStyle(theme.colors.ink2)
                    .multilineTextAlignment(.center)
            }
            action
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}

extension EmptyState where Action == EmptyView {
    init(icon: String, title: String, message: String? = nil) {
        self.icon = icon
        self.title = title
        self.message = message
        self.action = EmptyView()
    }
}

/**
 * Shapes where the content will be while a page loads, so the page keeps its
 * layout instead of jumping from a spinner to a list. They fade gently unless
 * motion is reduced.
 */
private struct Placeholder: ViewModifier {
    @Environment(\.kultr) private var theme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .opacity(dim ? 0.45 : 1)
            .onAppear {
                guard !systemReduceMotion, !theme.settings.reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
            }
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel("Loading")
    }
}

/** Track or list rows still loading: artwork, a title and a line under it. */
struct SkeletonRows: View {
    @Environment(\.kultr) private var theme
    var count = 8
    var artwork = true

    private static let widths: [(CGFloat, CGFloat)] = [(0.62, 0.38), (0.48, 0.3), (0.7, 0.44), (0.55, 0.26), (0.66, 0.4)]

    var body: some View {
        let fill = theme.colors.sand
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                let width = Self.widths[i % Self.widths.count]
                HStack(spacing: 12) {
                    if artwork {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill).frame(width: 44, height: 44)
                    }
                    GeometryReader { proxy in
                        VStack(alignment: .leading, spacing: 8) {
                            Capsule().fill(fill).frame(width: proxy.size.width * width.0, height: 12)
                            Capsule().fill(fill).frame(width: proxy.size.width * width.1, height: 10)
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                    }
                }
                .frame(height: 44)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .modifier(Placeholder())
    }
}

/** A grid of cards still loading, in the same columns as the real one. */
struct SkeletonGrid: View {
    @Environment(\.kultr) private var theme
    var count = 12
    /** Round, for artists. */
    var round = false

    var body: some View {
        let fill = theme.colors.sand
        LazyVGrid(columns: theme.settings.gridSize.columns, spacing: 16) {
            ForEach(0..<count, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    Group {
                        if round {
                            Circle().fill(fill)
                        } else {
                            RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous).fill(fill)
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    Capsule().fill(fill).frame(height: 12).padding(.trailing, 24)
                    Capsule().fill(fill).frame(height: 10).padding(.trailing, 56)
                }
            }
        }
        .padding(16)
        .modifier(Placeholder())
    }
}

/** An album, artist or playlist page still loading: the cover, the title, then tracks. */
struct SkeletonDetail: View {
    @Environment(\.kultr) private var theme

    var body: some View {
        let fill = theme.colors.sand
        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous)
                        .fill(fill)
                        .frame(width: 240, height: 240)
                        .padding(.top, 16)
                    Capsule().fill(fill).frame(width: 200, height: 18)
                    Capsule().fill(fill).frame(width: 140, height: 12)
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill).frame(height: 48)
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill).frame(height: 48)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .modifier(Placeholder())
                SkeletonRows(count: 6, artwork: false)
            }
        }
        .scrollDisabled(true)
    }
}

/** A filter that matches nothing. */
struct NoMatches: View {
    let query: String
    let what: String

    var body: some View {
        EmptyState(
            icon: "line.3.horizontal.decrease.circle",
            title: "No \(what) match “\(query)”",
            message: "Check the spelling, or try part of a name."
        )
        .padding(.top, 24)
    }
}

/** A settings-style row: label and hint on the left, a control on the right. */
struct SettingRow<Control: View>: View {
    @Environment(\.kultr) private var theme
    let label: String
    var hint: String?
    var action: (() -> Void)?
    @ViewBuilder var control: Control

    var body: some View {
        let row = HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(KFont.bodyLarge)
                    .foregroundStyle(theme.colors.ink)
                if let hint {
                    Text(hint)
                        .font(KFont.bodySmall)
                        .foregroundStyle(theme.colors.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        if let action {
            Button(action: action) { row }.buttonStyle(PressableStyle())
        } else {
            row
        }
    }
}

extension SettingRow where Control == EmptyView {
    init(_ label: String, hint: String? = nil, action: (() -> Void)? = nil) {
        self.label = label
        self.hint = hint
        self.action = action
        self.control = EmptyView()
    }
}

extension SettingRow {
    init(_ label: String, hint: String? = nil, action: (() -> Void)? = nil, @ViewBuilder control: () -> Control) {
        self.label = label
        self.hint = hint
        self.action = action
        self.control = control()
    }
}

/** A thin horizontal rule in the theme's line colour. */
struct Rule: View {
    @Environment(\.kultr) private var theme

    var body: some View {
        Rectangle().fill(theme.colors.line).frame(height: 1)
    }
}

/** The plain page colour behind screens. */
struct PlainBackdrop: View {
    @Environment(\.kultr) private var theme

    var body: some View {
        theme.colors.background.ignoresSafeArea()
    }
}

/** Blurred artwork behind everything, darkened so text stays readable. */
struct ArtworkBackdrop: View {
    @Environment(\.kultr) private var theme
    let coverId: String?
    @State private var image: UIImage?

    var body: some View {
        let url = artworkUrl(coverId, 96)
        ZStack {
            theme.colors.background
            if let image {
                // Sized to the space it is given: a square image filled to a
                // tall screen is wider than the screen, and must not widen it.
                GeometryReader { proxy in
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(1.2)
                        .clipped()
                }
                .opacity(theme.colors.night ? 0.32 : theme.colors.dark ? 0.6 : 0.5)
                .transition(.opacity)
                .id(url)
            }
            // Flat, so text reads the same at the top and the bottom.
            theme.colors.background.opacity(0.55)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            if let hit = ImageLoader.shared.cachedBlur(url) {
                image = hit
                return
            }
            let next = await ImageLoader.shared.blurred(url)
            withAnimation(theme.reduceMotion ? nil : .easeInOut(duration: 0.6)) { image = next }
        }
    }
}

/** What goes behind every page: the blurred artwork of what is playing, or the plain field. */
struct AppBackdrop: View {
    @Environment(\.kultr) private var theme

    var body: some View {
        let current = AppGraph.shared.player.state.current
        if theme.settings.backdropArtwork, let current {
            ArtworkBackdrop(coverId: current.artworkId)
        } else {
            PlainBackdrop()
        }
    }
}

extension View {
    /** A page in a tab's navigation stack: Kultr's own background behind iOS's navigation bar. */
    func kultrScreen() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background { AppBackdrop() }
    }
}

/** A horizontally scrolling row of cards. */
struct Shelf<Item: Identifiable, Card: View>: View {
    let items: [Item]
    var cardWidth: CGFloat = 150
    @ViewBuilder let card: (Item) -> Card

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(items) { item in
                    card(item).frame(width: cardWidth)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

/** Kultr's switch, tinted with the accent. */
struct KultrSwitch: View {
    @Environment(\.kultr) private var theme
    let isOn: Bool
    var enabled = true
    let onChange: (Bool) -> Void

    var body: some View {
        Toggle("", isOn: Binding(get: { isOn }, set: { onChange($0) }))
            .labelsHidden()
            .tint(theme.colors.accent)
            .disabled(!enabled)
    }
}

/** A thin progress bar in the accent. */
struct ProgressBar: View {
    @Environment(\.kultr) private var theme
    /** 0..1, or nil for an indeterminate bar. */
    let value: Double?
    var height: CGFloat = 4

    var body: some View {
        if let value {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.colors.ink4)
                    Capsule().fill(theme.colors.accent).frame(width: proxy.size.width * min(1, max(0, value)))
                }
            }
            .frame(height: height)
        } else {
            ProgressView().progressViewStyle(.linear).tint(theme.colors.accent)
        }
    }
}
