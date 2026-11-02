import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
private func studio<T>(_ path: WritableKeyPath<Settings, T>) -> Binding<T> {
    Binding(
        get: { AppGraph.shared.settings.settings[keyPath: path] },
        set: { value in AppGraph.shared.settings.update { $0[keyPath: path] = value } }
    )
}

/**
 * Kultr Studio: the whole look in one place. Start from a style, change the
 * colours, the shape, the glass and how the player is put together, see it
 * in the preview as you go, and share it as a link or a file.
 */
struct StudioScreen: View {
    @Environment(\.kultr) private var theme
    @State private var name = "My style"
    @State private var importing = false
    @State private var incoming: StudioStyle?

    var body: some View {
        let graph = AppGraph.shared
        let s = theme.settings
        let c = theme.colors
        let current = StudioStyle(settings: s, name: name)
        Form {
            Section {
                StudioPreview()
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(STUDIO_PRESETS, id: \.name) { preset in
                            PresetCard(style: preset, chosen: preset.matches(s)) {
                                Haptics.select()
                                withAnimation(theme.ease) { graph.settings.replace(preset.applied(to: s)) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } header: {
                Text("Start from a style")
            } footer: {
                Text("A style is only the look: your library, servers and other settings stay as they are.")
            }

            Section("Colours") {
                Picker("Theme", selection: studio(\.theme)) {
                    Text("System").tag(ThemeMode.system)
                    Text("Light").tag(ThemeMode.light)
                    Text("Dark").tag(ThemeMode.dark)
                }
                Toggle("Night mode (pure black)", isOn: studio(\.nightMode)).tint(c.accent)
                Toggle("Colour from the artwork", isOn: Binding(get: { s.accentMode == .artwork }, set: { on in graph.settings.update { $0.accentMode = on ? .artwork : .fixed } }))
                    .tint(c.accent)
                Toggle("Blurred cover behind the player", isOn: studio(\.backdropArtwork)).tint(c.accent)
                NavigationLink("Accent colour and more") { AppearanceSettingsLink() }
            }

            Section("Shape and glass") {
                Picker("Corners", selection: studio(\.corners)) {
                    Text("Sharp").tag(CornerStyle.sharp)
                    Text("Soft").tag(CornerStyle.soft)
                    Text("Round").tag(CornerStyle.round)
                }
                Picker("Grid", selection: studio(\.gridSize)) {
                    Text("Small covers").tag(GridSize.small)
                    Text("Medium covers").tag(GridSize.medium)
                    Text("Large covers").tag(GridSize.large)
                }
                Toggle("Compact rows", isOn: studio(\.compactRows)).tint(c.accent)
                Toggle("Clear glass", isOn: studio(\.clearGlass)).tint(c.accent)
                Picker("Playhead", selection: studio(\.playhead)) {
                    ForEach(PlayheadStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }

            Section {
                ForEach(orderedBlocks(s.playerBlocks), id: \.self) { block in
                    let on = s.playerBlocks.contains(block)
                    HStack {
                        Image(systemName: "line.3.horizontal").foregroundStyle(c.ink4)
                        Toggle(block.label, isOn: Binding(get: { on }, set: { show in
                            graph.settings.update { settings in
                                if show {
                                    if !settings.playerBlocks.contains(block) { settings.playerBlocks.append(block) }
                                } else if settings.playerBlocks.count > 1 {
                                    settings.playerBlocks.removeAll { $0 == block }
                                }
                            }
                        }))
                        .tint(c.accent)
                    }
                }
                .onMove { from, to in
                    var all = orderedBlocks(s.playerBlocks)
                    all.move(fromOffsets: from, toOffset: to)
                    let shown = Set(s.playerBlocks)
                    graph.settings.update { $0.playerBlocks = all.filter { shown.contains($0) } }
                }
            } header: {
                Text("The player, top to bottom")
            } footer: {
                Text("Hold a row and drag it to move it. Switch a part off to hide it.")
            }

            Section {
                TextField("Kultr's own line", text: studio(\.factsTemplate), axis: .vertical)
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(TEMPLATE_FIELDS, id: \.name) { field in
                            Button {
                                graph.settings.update { settings in
                                    let joiner = settings.factsTemplate.isEmpty ? "" : " · "
                                    settings.factsTemplate += "{?\(field.name):\(joiner){\(field.name)}}"
                                }
                            } label: {
                                Text(field.name)
                                    .font(KFont.labelLarge)
                                    .foregroundStyle(c.accent)
                                    .padding(.horizontal, 12)
                                    .frame(height: 30)
                                    .background(Capsule().fill(c.sand))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    Text("Looks like").foregroundStyle(c.ink3)
                    Spacer()
                    Text(s.factsTemplate.isEmpty ? "2019 · Electronic · FLAC" : renderTemplate(s.factsTemplate, Dictionary(uniqueKeysWithValues: TEMPLATE_FIELDS.map { ($0.name, $0.example) })))
                        .foregroundStyle(c.ink)
                        .lineLimit(1)
                }
                if !s.factsTemplate.isEmpty {
                    Button("Back to Kultr's own line") { graph.settings.update { $0.factsTemplate = "" } }
                }
            } header: {
                Text("The info line")
            } footer: {
                Text("{bpm} puts the tempo in. {?genre: · {genre}} shows the genre, and its dot, only when a track has one. Tap a name to add it.")
            }

            Section {
                TextField("Style name", text: $name)
                ShareLink(item: current.link, subject: Text(name), message: Text("A Kultr style: \(name)")) {
                    Label("Share as a link", systemImage: "link")
                }
                ShareLink(item: StyleFile(style: current), preview: SharePreview(name, image: Image(systemName: "paintpalette"))) {
                    Label("Share as a file", systemImage: "doc")
                }
                Button {
                    UIPasteboard.general.string = current.link
                    graph.messages.show("Style link copied")
                } label: {
                    Label("Copy the link", systemImage: "doc.on.doc")
                }
                Button {
                    if let text = UIPasteboard.general.string, let style = StudioStyle.read(text) {
                        incoming = style
                    } else {
                        graph.messages.show("There's no Kultr style link on the clipboard.")
                    }
                } label: {
                    Label("Use a link from the clipboard", systemImage: "doc.on.clipboard")
                }
                Button { importing = true } label: {
                    Label("Open a style file", systemImage: "folder")
                }
            } header: {
                Text("Share")
            } footer: {
                Text("Someone opening your link sees the style first, then chooses whether to use it.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(c.background)
        .navigationTitle("Kultr Studio")
        .navigationBarTitleDisplayMode(.large)
        .tint(c.accent)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let text = try? String(contentsOf: url, encoding: .utf8), let style = StudioStyle.read(text) {
                incoming = style
            } else {
                graph.messages.error("That file isn't a Kultr style.")
            }
        }
        .sheet(item: Binding(get: { incoming.map(IncomingStyle.init) }, set: { incoming = $0?.style })) { item in
            StylePreviewSheet(style: item.style) { incoming = nil }
                .environment(\.kultr, theme)
        }
    }

    /** Every block: the shown ones in their order, then the hidden ones. */
    private func orderedBlocks(_ shown: [PlayerBlock]) -> [PlayerBlock] {
        shown + PlayerBlock.allCases.filter { !shown.contains($0) }
    }
}

/** Appearance, opened from Studio for the accent colours and the rest. */
private struct AppearanceSettingsLink: View {
    var body: some View {
        AppearanceSettings()
    }
}

struct IncomingStyle: Identifiable {
    let style: StudioStyle
    var id: String { style.link }
}

/** A style as a file to share. */
struct StyleFile: Transferable {
    let style: StudioStyle

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { file in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(file.style)
        }
        .suggestedFileName { "\($0.style.name).kultrstyle.json" }
    }
}

/** A style card: its page colour, its accent and its corners, and its name. */
private struct PresetCard: View {
    @Environment(\.kultr) private var theme
    let style: StudioStyle
    let chosen: Bool
    let action: () -> Void

    var body: some View {
        let c = theme.colors
        let dark = style.theme == .dark || (style.theme == .system && theme.colors.dark)
        let page = style.nightMode && dark ? Color.black : (dark ? Color(argb: 0xFF1C1A17) : Color(argb: 0xFFF6F0E5))
        let ink = dark ? Color.white : Color(argb: 0xFF1F1A14)
        let accent = Color(argb: ArtworkColor.parseHex(style.accent) ?? 0xFFFF7A3D)
        let radius: CGFloat = style.corners == .sharp ? 4 : (style.corners == .soft ? 10 : 18)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(page)
                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: radius / 2, style: .continuous).fill(ink.opacity(0.15)).frame(width: 40, height: 40)
                        Capsule().fill(ink.opacity(0.8)).frame(width: 52, height: 5)
                        Capsule().fill(accent).frame(width: 34, height: 5)
                    }
                    .padding(10)
                }
                .frame(width: 104, height: 96)
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(chosen ? c.accent : c.ink4, lineWidth: chosen ? 3 : 1))
                HStack(spacing: 4) {
                    Text(style.name).font(KFont.labelLarge).foregroundStyle(c.ink)
                    if chosen { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(c.accent) }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Style \(style.name)")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/** The player in miniature, built from the blocks in their order, in the look as it is now. */
private struct StudioPreview: View {
    @Environment(\.kultr) private var theme

    var body: some View {
        let s = theme.settings
        let c = theme.colors
        let values = Dictionary(uniqueKeysWithValues: TEMPLATE_FIELDS.map { ($0.name, $0.example) })
        VStack(spacing: 8) {
            ForEach(s.playerBlocks, id: \.self) { block in
                switch block {
                case .artwork:
                    RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous)
                        .fill(c.accent.opacity(0.25))
                        .overlay(Image(systemName: "music.note").font(.largeTitle).foregroundStyle(c.accent))
                        .frame(width: 120, height: 120)
                case .title:
                    VStack(spacing: 2) {
                        Text("Paper Moons").font(.headline).foregroundStyle(c.ink)
                        Text("Ama Okoro — Night Ferries").font(.subheadline).foregroundStyle(c.ink2)
                    }
                case .facts:
                    Text(s.factsTemplate.isEmpty ? "2019 · Electronic · FLAC" : renderTemplate(s.factsTemplate, values))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(c.ink3)
                case .progress:
                    ZStack(alignment: .leading) {
                        Capsule().fill(c.ink4).frame(height: 4)
                        Capsule().fill(c.accent).frame(width: 90, height: 4)
                    }
                    .frame(width: 220)
                case .transport:
                    HStack(spacing: 28) {
                        Image(systemName: "backward.end.fill")
                        Image(systemName: "pause.fill").font(.title)
                        Image(systemName: "forward.end.fill")
                    }
                    .foregroundStyle(c.ink)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous).fill(c.background))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous).strokeBorder(c.ink4, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the player in this style")
    }
}

/** A style someone shared: what it looks like, and the choice to use it. */
struct StylePreviewSheet: View {
    @Environment(\.kultr) private var theme
    let style: StudioStyle
    let onDone: () -> Void

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        let look = style.applied(to: theme.settings)
        let dark = style.theme == .dark || (style.theme == .system && c.dark)
        let preview = KultrTheme(
            colors: .make(dark: dark, accent: ArtworkColor.parseHex(look.accent).map { $0 & 0xFFFFFF } ?? 0xFF7A3D, settings: look),
            radii: .of(look.corners),
            settings: look
        )
        VStack(spacing: 16) {
            Text("“\(style.name)”")
                .font(.title2.bold())
                .foregroundStyle(c.ink)
                .padding(.top, 24)
            Text("A Kultr style someone shared: the look only, nothing else.")
                .font(KFont.bodyMedium)
                .foregroundStyle(c.ink2)
                .multilineTextAlignment(.center)
            StudioPreview()
                .environment(\.kultr, preview)
                .padding(.horizontal, 16)
            Spacer(minLength: 0)
            WideButton(title: "Use this style", icon: "paintpalette.fill", prominent: true) {
                graph.settings.replace(style.applied(to: graph.settings.current))
                graph.messages.show("Now using “\(style.name)”", .success)
                onDone()
            }
            .padding(.horizontal, 16)
            TextButton("Not now", color: c.ink2, action: onDone)
                .padding(.bottom, 16)
        }
        .background(c.background)
        .presentationDetents([.large])
    }
}
