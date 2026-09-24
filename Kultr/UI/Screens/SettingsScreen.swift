import SwiftUI
import UniformTypeIdentifiers

private let ACCENTS = ["#7c8cff", "#ff6b9a", "#ff9f43", "#ffd166", "#45d67a", "#2ec4b6", "#4cc9f0", "#b388ff", "#f5f5f7"]
private let BITRATES: [(Int, String)] = [(0, "Original"), (320, "320 kbps"), (256, "256 kbps"), (192, "192 kbps"), (128, "128 kbps"), (96, "96 kbps")]
private let WEBSITE = "https://kultr.cc/"
private let DISCORD = "https://discord.com/users/319246364246540288"
private let SOURCE = "https://github.com/evropiani/Kultr_iOS"

@MainActor
private func update(_ change: (inout Settings) -> Void) {
    AppGraph.shared.settings.update(change)
}

private func signed(_ value: Double) -> String {
    let rounded = Int(value.rounded())
    return rounded > 0 ? "+\(rounded) dB" : "\(rounded) dB"
}

struct SettingsScreen: View {
    @Environment(\.kultr) private var theme
    @State private var open: Set<String> = []

    var body: some View {
        let s = theme.settings
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .font(KFont.headlineMedium)
                    .foregroundStyle(theme.colors.ink)
                    .padding(.leading, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                section("Appearance", "paintpalette.fill") { AppearanceSettings(s: s) }
                section("Home page", "house.fill") { HomeSettings(s: s) }
                section("Playback", "play.circle.fill") { PlaybackSettings(s: s) }
                section("InjeKt", "sparkles") { InjektSettings(s: s) }
                section("Audio", "waveform") { AudioSettings(s: s) }
                section("Equaliser", "slider.vertical.3") { EqualiserSettings(s: s) }
                section("Offline and cache", "arrow.down.circle.fill") { OfflineSettings(s: s) }
                section("Servers", "server.rack") { ServerSettings() }
                section("Backup and reset", "externaldrive.fill") { BackupSettings() }
                section("About", "info.circle.fill") { AboutSection() }
            }
            .padding(.bottom, 32)
        }
        .kultrScreen()
    }

    private func section<Content: View>(_ title: String, _ icon: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        SettingsSection(title: title, icon: icon, expanded: open.contains(title), onToggle: {
            withAnimation(.easeOut(duration: 0.2)) {
                if open.contains(title) { open.remove(title) } else { open.insert(title) }
            }
        }, content: content)
    }
}

private struct SettingsSection<Content: View>: View {
    @Environment(\.kultr) private var theme
    let title: String
    let icon: String
    let expanded: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        let c = theme.colors
        GlassPanel(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: onToggle) {
                    HStack(spacing: 12) {
                        Image(systemName: icon).foregroundStyle(c.accent).frame(width: 24)
                        Text(title).font(KFont.titleMedium).foregroundStyle(c.ink)
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").foregroundStyle(c.ink3)
                    }
                    .padding(16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if expanded {
                    VStack(alignment: .leading, spacing: 0) { content() }
                        .padding(.bottom, 8)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }
}

// ------------------------------------------------------------- controls --

private struct SettingToggle: View {
    let label: String
    let checked: Bool
    var hint: String?
    var enabled = true
    let onChange: (Bool) -> Void

    init(_ label: String, _ checked: Bool, hint: String? = nil, enabled: Bool = true, onChange: @escaping (Bool) -> Void) {
        self.label = label
        self.checked = checked
        self.hint = hint
        self.enabled = enabled
        self.onChange = onChange
    }

    var body: some View {
        SettingRow(label, hint: hint, action: enabled ? { onChange(!checked) } : nil) {
            KultrSwitch(isOn: checked, enabled: enabled, onChange: onChange)
        }
        .opacity(enabled ? 1 : 0.5)
    }
}

private struct Choice<T: Hashable>: View {
    @Environment(\.kultr) private var theme
    let label: String
    let options: [(T, String)]
    let selected: T
    var hint: String?
    let onSelect: (T) -> Void

    init(_ label: String, _ options: [(T, String)], _ selected: T, hint: String? = nil, onSelect: @escaping (T) -> Void) {
        self.label = label
        self.options = options
        self.selected = selected
        self.hint = hint
        self.onSelect = onSelect
    }

    var body: some View {
        let c = theme.colors
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(KFont.bodyLarge).foregroundStyle(c.ink)
            if let hint { Text(hint).font(KFont.bodySmall).foregroundStyle(c.ink3) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                        Pill(option.1, accent: option.0 == selected) { onSelect(option.0) }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)
            .padding(.top, 6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/** A slider that keeps its own value while dragging and commits when released. */
private struct SettingSlider: View {
    @Environment(\.kultr) private var theme
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let format: (Double) -> String
    var hint: String?
    var enabled = true
    let onCommit: (Double) -> Void
    @State private var local: Double?

    var body: some View {
        let c = theme.colors
        let shown = local ?? value
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(KFont.bodyLarge).foregroundStyle(enabled ? c.ink : c.ink3)
                Spacer()
                Text(format(shown)).font(KFont.bodyMedium.weight(.semibold)).foregroundStyle(c.accent)
            }
            if let hint { Text(hint).font(KFont.bodySmall).foregroundStyle(c.ink3) }
            Slider(
                value: Binding(get: { local ?? value }, set: { local = $0 }),
                in: range,
                step: step,
                onEditingChanged: { editing in
                if !editing, let committed = local {
                    onCommit(committed)
                    local = nil
                }
            })
            .tint(c.accent)
            .disabled(!enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

// ----------------------------------------------------------- appearance --

private struct AppearanceSettings: View {
    @Environment(\.kultr) private var theme
    let s: Settings

    var body: some View {
        let c = theme.colors
        Choice("Theme", [(ThemeMode.dark, "Dark"), (ThemeMode.light, "Light"), (ThemeMode.system, "System")], s.theme) { v in update { $0.theme = v } }
        SettingToggle("Colour from artwork", s.accentMode == .artwork, hint: "The interface takes its colour from whatever is playing.") { v in
            update { $0.accentMode = v ? .artwork : .fixed }
        }
        VStack(alignment: .leading, spacing: 8) {
            Text(s.accentMode == .artwork ? "Your colour" : "Accent colour").foregroundStyle(c.ink)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ACCENTS, id: \.self) { hex in
                        let selected = s.accent.lowercased() == hex
                        Button {
                            update { $0.accent = hex }
                        } label: {
                            ZStack {
                                Circle().fill(Color(argb: ArtworkColor.parseHex(hex) ?? 0))
                                Circle().strokeBorder(selected ? c.ink : c.line, lineWidth: selected ? 3 : 1)
                                if selected {
                                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.black.opacity(0.7))
                                }
                            }
                            .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Accent \(hex)")
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        if s.accentMode == .artwork {
            SettingSlider(label: "How much of your colour", value: Double(s.accentBlend), range: 0...100, format: { "\(Int($0))%" }, hint: "0% is pure artwork colour; 100% ignores the artwork.") { v in
                update { $0.accentBlend = Int(v) }
            }
        }
        SettingToggle("Blurred artwork background", s.backdropArtwork) { v in update { $0.backdropArtwork = v } }
        Choice("Corners", [(CornerStyle.sharp, "Sharp"), (CornerStyle.soft, "Soft"), (CornerStyle.round, "Round")], s.corners) { v in update { $0.corners = v } }
        Choice("Panel borders", [(SurfaceBorder.neutral, "Neutral"), (SurfaceBorder.accent, "Accent")], s.surfaceBorder) { v in update { $0.surfaceBorder = v } }
        SettingSlider(label: "Border opacity", value: Double(s.borderOpacity), range: 0...100, format: { "\(Int($0))%" }) { v in update { $0.borderOpacity = Int(v) } }
        SettingSlider(label: "Panel opacity", value: Double(s.surfaceOpacity), range: 0...200, format: { "\(Int($0))%" }) { v in update { $0.surfaceOpacity = Int(v) } }
        Choice("Grid size", [(GridSize.small, "Small"), (GridSize.medium, "Medium"), (GridSize.large, "Large")], s.gridSize) { v in update { $0.gridSize = v } }
        SettingToggle("Compact track rows", s.compactRows) { v in update { $0.compactRows = v } }
        Choice("Playhead", PlayheadStyle.allCases.map { ($0, $0.label) }, s.playhead, hint: s.playhead.note) { v in update { $0.playhead = v } }
        SettingToggle("Count time down", s.timeRemaining, hint: "Show how much of the track is left. Tapping the time in the player switches it too.") { v in
            update { $0.timeRemaining = v }
        }
        SettingToggle("Show the lyrics tab", s.showLyrics) { v in update { $0.showLyrics = v } }
        SettingToggle("Reduce motion", s.reduceMotion, hint: "Stops animated colour changes and playhead effects.") { v in update { $0.reduceMotion = v } }
    }
}

// ------------------------------------------------------------ home page --

private struct HomeSettings: View {
    @Environment(\.kultr) private var theme
    let s: Settings

    var body: some View {
        let c = theme.colors
        let on = resolveHomeTiles(s.homeTiles)
        let off = availableHomeTiles(s.homeTiles)
        let ids = on.map { $0.id }
        Text("Shelves are shown in this order. One with nothing in it is skipped.")
            .font(KFont.bodySmall)
            .foregroundStyle(c.ink3)
            .padding(.horizontal, 16)
        ForEach(Array(on.enumerated()), id: \.element.id) { index, tile in
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tile.title).foregroundStyle(c.ink)
                    Text(tile.note).font(KFont.bodySmall).foregroundStyle(c.ink3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                IconButton(icon: "chevron.up", tint: index > 0 ? c.ink2 : c.ink4, label: "Move up") {
                    guard index > 0 else { return }
                    var next = ids
                    next.swapAt(index, index - 1)
                    update { $0.homeTiles = next }
                }
                IconButton(icon: "chevron.down", tint: index < on.count - 1 ? c.ink2 : c.ink4, label: "Move down") {
                    guard index < on.count - 1 else { return }
                    var next = ids
                    next.swapAt(index, index + 1)
                    update { $0.homeTiles = next }
                }
                IconButton(icon: "xmark", tint: c.ink2, label: "Remove from the home page") {
                    update { $0.homeTiles = ids.filter { $0 != tile.id } }
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 4)
        }
        if !off.isEmpty {
            Menu {
                ForEach(off) { tile in
                    Button {
                        update { $0.homeTiles = ids + [tile.id] }
                    } label: {
                        Text(tile.title)
                        Text(tile.note)
                    }
                }
            } label: {
                PillLabel(text: "Add a shelf", icon: "plus")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

// ------------------------------------------------------------- playback --

private struct PlaybackSettings: View {
    let s: Settings

    var body: some View {
        SettingToggle("Crossfade between tracks", s.crossfadeEnabled, hint: "Two decks play at once for the length of the fade.") { v in update { $0.crossfadeEnabled = v } }
        SettingSlider(label: "Crossfade length", value: s.crossfadeSeconds, range: 1...20, format: { "\(Int($0)) s" }, enabled: s.crossfadeEnabled) { v in
            update { $0.crossfadeSeconds = v.rounded() }
        }
        Choice("Fade shape", CrossfadeCurve.allCases.map { ($0, $0.label) }, s.crossfadeCurve) { v in update { $0.crossfadeCurve = v } }
        SettingToggle("Also fade when you skip", s.crossfadeOnSkip, hint: "A short fade instead of a hard cut on next and previous.") { v in update { $0.crossfadeOnSkip = v } }
        SettingToggle("Gapless playback", s.gapless, hint: "With crossfade off, the next track starts the instant this one ends.") { v in update { $0.gapless = v } }
        SettingToggle("Resume where you left off", s.resumeOnStart, hint: "Restores the queue and position when Kultr opens.") { v in update { $0.resumeOnStart = v } }
        SettingToggle(
            "Send plays to Navidrome",
            s.scrobble,
            hint: "Counts each play on your server, so recently and most played are the same on every device and survive reinstalling. Plays made offline are sent, with their real time, once you are back."
        ) { v in update { $0.scrobble = v } }
    }
}

// --------------------------------------------------------------- injekt --

private struct InjektSettings: View {
    let s: Settings

    var body: some View {
        let on = s.injektEnabled
        SettingToggle("Enable InjeKt", on, hint: "Beat-matched, key-aware transitions planned from each track's tempo, key and structure.") { v in
            update { $0.injektEnabled = v }
        }
        SettingToggle("Beat-match", s.injektBeatMatch, hint: "Bring both tracks to a shared tempo and line up their bars.", enabled: on) { v in update { $0.injektBeatMatch = v } }
        SettingToggle("Meet in the middle", s.injektTempoRamp, hint: "Ease the current track toward the next one's tempo before the blend.", enabled: on) { v in
            update { $0.injektTempoRamp = v }
        }
        SettingSlider(
            label: "Tempo share",
            value: s.injektTempoBlend,
            range: 0...100,
            format: { "\(Int($0))%" },
            hint: "How much of the tempo change the outgoing track makes.",
            enabled: on && s.injektTempoRamp
        ) { v in update { $0.injektTempoBlend = v.rounded() } }
        SettingSlider(
            label: "Maximum tempo shift",
            value: s.injektMaxTempoShift,
            range: 2...16,
            format: { "\(Int($0))%" },
            hint: "Per track. Further apart than this, tracks are crossfaded instead.",
            enabled: on
        ) { v in update { $0.injektMaxTempoShift = v.rounded() } }
        Choice("Transition length", [(4, "4 bars"), (8, "8 bars"), (16, "16 bars"), (32, "32 bars")], s.injektBars, hint: "Shortened automatically when two tracks clash.") { v in
            update { $0.injektBars = v }
        }
        SettingToggle("Bass swap", s.injektBassSwap, hint: "Roll the outgoing bass off before the incoming bass comes up.", enabled: on) { v in update { $0.injektBassSwap = v } }
        SettingToggle("Harmonic mixing", s.injektHarmonic, hint: "When keys clash, filter out of the old track instead of blending.", enabled: on) { v in update { $0.injektHarmonic = v } }
        SettingToggle("Skip long intros", s.injektSkipIntro, hint: "Bring the next track in at its first real downbeat.", enabled: on) { v in update { $0.injektSkipIntro = v } }
        SettingToggle("Keep playing similar music", s.injektAutoQueue, hint: "When the queue runs out, continue with tracks chosen by tempo, key and energy.") { v in
            update { $0.injektAutoQueue = v }
        }
        SettingToggle(
            "Analyse ahead",
            s.injektAnalyseAhead,
            hint: "The current and next track are always analysed when a track starts. This also measures the one after, so skipping ahead lands on a transition that is ready too.",
            enabled: on
        ) { v in update { $0.injektAnalyseAhead = v } }
        SettingToggle("Analyse on Wi-Fi only", s.injektAnalyseOnWifiOnly, hint: "Never spend mobile data on analysis.", enabled: on) { v in
            update { $0.injektAnalyseOnWifiOnly = v }
        }
    }
}

// ---------------------------------------------------------------- audio --

private struct AudioSettings: View {
    let s: Settings

    var body: some View {
        Choice("Volume levelling (ReplayGain)", ReplayGainMode.allCases.map { ($0, $0.label) }, s.replayGainMode) { v in update { $0.replayGainMode = v } }
        SettingSlider(label: "ReplayGain pre-amp", value: s.replayGainPreamp, range: -12...12, format: signed, enabled: s.replayGainMode != .off) { v in
            update { $0.replayGainPreamp = v.rounded() }
        }
        Choice("Streaming quality on Wi-Fi", BITRATES, s.preferredBitrate, hint: "Lower bitrates are transcoded by your server.") { v in update { $0.preferredBitrate = v } }
        Choice("Streaming quality on mobile data", [(-1, "Same as Wi-Fi")] + BITRATES, s.preferredBitrateMobile) { v in update { $0.preferredBitrateMobile = v } }
        Choice(
            "Transcode format",
            [("", "Server default"), ("mp3", "MP3"), ("aac", "AAC")],
            ["", "mp3", "aac"].contains(s.preferredFormat) ? s.preferredFormat : "",
            hint: "Used when a lower bitrate is chosen. iPhones cannot play Opus or Vorbis streams, so those are not offered."
        ) { v in update { $0.preferredFormat = v } }
    }
}

// ------------------------------------------------------------ equaliser --

private struct EqualiserSettings: View {
    let s: Settings

    var body: some View {
        let gains = s.eqBandGains
        SettingToggle("Enable the equaliser", s.eqEnabled) { v in update { $0.eqEnabled = v } }
        Choice("Preset", EQ_PRESET_LIST.map { ($0.name, $0.name) } + (EQ_PRESETS[s.eqPreset] == nil ? [(s.eqPreset, s.eqPreset)] : []), s.eqPreset) { name in
            AppGraph.shared.settings.replace(AppGraph.shared.settings.current.withEqPreset(name))
        }
        ForEach(Array(EQ_BANDS.enumerated()), id: \.offset) { index, hz in
            SettingSlider(
                label: hz >= 1000 ? "\(hz / 1000) kHz" : "\(hz) Hz",
                value: gains[index],
                range: -12...12,
                format: signed,
                enabled: s.eqEnabled
            ) { v in
                update { st in
                    var next = st.eqBandGains
                    next[index] = v.rounded()
                    st.eqGains = next
                    st.eqPreset = "Custom"
                }
            }
        }
        SettingSlider(label: "Pre-amp", value: s.eqPreamp, range: -12...6, format: signed, hint: "Pull this down if the equaliser makes things clip.", enabled: s.eqEnabled) { v in
            update { $0.eqPreamp = v.rounded() }
        }
    }
}

// -------------------------------------------------------------- offline --

private struct OfflineSettings: View {
    let s: Settings

    var body: some View {
        let graph = AppGraph.shared
        SettingSlider(label: "Parallel downloads", value: Double(s.offlineConcurrency), range: 1...8, format: { "\(Int($0))" }) { v in
            update { $0.offlineConcurrency = Int(v) }
        }
        Choice("Download quality", BITRATES, s.offlineBitrate, hint: "Original keeps the file exactly as it is on the server.") { v in update { $0.offlineBitrate = v } }
        SettingToggle("Download on Wi-Fi only", s.offlineWifiOnly) { v in update { $0.offlineWifiOnly = v } }
        SettingToggle("Prefer offline copies", s.offlineFirst, hint: "Play a downloaded file instead of streaming when one exists.") { v in update { $0.offlineFirst = v } }
        Choice(
            "Stream cache",
            [(256, "256 MB"), (1024, "1 GB"), (2048, "2 GB"), (4096, "4 GB"), (8192, "8 GB")],
            s.streamCacheMb,
            hint: "Recently streamed audio is kept so replays do not refetch."
        ) { v in update { $0.streamCacheMb = v } }
        HStack(spacing: 8) {
            Pill("Clear stream cache") {
                graph.clearMediaCache()
                graph.messages.show("Stream cache cleared.")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// -------------------------------------------------------------- servers --

private struct ServerSettings: View {
    @Environment(\.kultr) private var theme
    @State private var forget: ServerProfile?

    var body: some View {
        let graph = AppGraph.shared
        let auth = graph.auth
        let c = theme.colors
        let activeId = auth.active?.id
        ForEach(auth.profiles) { profile in
            let isActive = profile.id == activeId
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.label + (isActive ? " · in use" : ""))
                        .font(KFont.bodyLarge.weight(.semibold))
                        .foregroundStyle(isActive ? c.accent : c.ink)
                        .lineLimit(1)
                    Text([profile.username.isEmpty ? "not signed in" : profile.username, profile.serverUrl].joined(separator: " · "))
                        .font(KFont.bodySmall)
                        .foregroundStyle(c.ink3)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !profile.hasCredentials {
                    TextButton("Sign in") { graph.ui.login = LoginRequest(url: profile.serverUrl, user: profile.username) }
                } else if !isActive && profile.enabled {
                    TextButton("Use") { _ = auth.switchTo(profile.id) }
                }
                KultrSwitch(isOn: profile.enabled) { auth.setEnabled(profile.id, $0) }
                IconButton(icon: "xmark", tint: c.ink3, label: "Forget \(profile.label)") { forget = profile }
            }
            .padding(.leading, 16)
            .padding(.trailing, 4)
            .padding(.vertical, 6)
        }
        HStack(spacing: 8) {
            Pill("Add a server", icon: "plus") { graph.ui.login = LoginRequest() }
            if auth.active != nil {
                Pill("Sign out", icon: "rectangle.portrait.and.arrow.right") {
                    graph.player.stop()
                    auth.signOut()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .alert(
            "Forget \(forget?.label ?? "")?",
            isPresented: Binding(get: { forget != nil }, set: { if !$0 { forget = nil } }),
            presenting: forget
        ) { profile in
            Button("Cancel", role: .cancel) {}
            Button("Forget", role: .destructive) {
                if profile.id == auth.active?.id { graph.player.stop() }
                _ = auth.remove(profile.id)
                graph.deleteDataFor(profile.id)
            }
        } message: { _ in
            Text("Its saved password, synced library, downloads and listening history on this phone are deleted. Nothing changes on the server.")
        }
    }
}

// --------------------------------------------------------------- backup --

private struct JsonDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private struct BackupSettings: View {
    @Environment(\.kultr) private var theme
    @State private var includeServers = false
    @State private var exporting = false
    @State private var importing = false
    @State private var document = JsonDocument(text: "")
    @State private var confirmReset = false
    @State private var confirmWipe = false
    @State private var report: String?

    var body: some View {
        let graph = AppGraph.shared
        Text("Export every preference to a small file and import it on another phone, or in Kultr on the web or Android. Passwords and usernames are never in it.")
            .font(KFont.bodySmall)
            .foregroundStyle(theme.colors.ink3)
            .padding(.horizontal, 16)
        SettingToggle("Include the list of servers", includeServers, hint: "Addresses only — never usernames or passwords.") { includeServers = $0 }
        HStack(spacing: 8) {
            Pill("Export settings") {
                let servers = includeServers
                    ? graph.auth.profiles.map { SettingsFile.ExportedServer(label: $0.label, serverUrl: $0.serverUrl, authMode: $0.authMode) }
                    : nil
                document = JsonDocument(
                    text: SettingsFile.export(graph.settings.current, appVersion: appVersion, exportedAt: ISO8601DateFormatter().string(from: Date()), servers: servers)
                )
                exporting = true
            }
            Pill("Import settings") { importing = true }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        HStack(spacing: 8) {
            Pill("Reset settings") { confirmReset = true }
            Pill("Clear library data") { confirmWipe = true }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .fileExporter(
            isPresented: $exporting,
            document: document,
            contentType: .json,
            defaultFilename: "kultr-settings-\(ISO8601DateFormatter().string(from: Date()).prefix(10)).json"
        ) { result in
            switch result {
            case .success: graph.messages.success("Settings exported.")
            case .failure(let error): graph.messages.error("Could not write the file: \(error.localizedDescription)")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText, .data]) { result in
            switch result {
            case .success(let url): importFrom(url)
            case .failure(let error): graph.messages.error(error.localizedDescription)
            }
        }
        .alert("Settings imported", isPresented: Binding(get: { report != nil }, set: { if !$0 { report = nil } })) {
            Button("OK", role: .cancel) { report = nil }
        } message: {
            Text(report ?? "")
        }
        .alert("Reset every setting?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { graph.settings.reset() }
        } message: {
            Text("Appearance, playback, InjeKt and everything else go back to their defaults. Servers are kept.")
        }
        .alert("Clear library data?", isPresented: $confirmWipe) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                Task {
                    await graph.library.clearLibraryData()
                    graph.messages.show("Library data cleared.")
                }
            }
        } message: {
            Text("The synced library, InjeKt analysis and listening history for this server are deleted from this phone. Downloads are kept. Sync again to rebuild the library.")
        }
    }

    private func importFrom(_ url: URL) {
        let graph = AppGraph.shared
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let result = try SettingsFile.importFile(text, current: graph.settings.current)
            graph.settings.replace(result.settings)
            let added = graph.auth.importServers(result.servers)
            var message = "Applied \(result.applied.count) settings"
            if added > 0 { message += " and added \(added) server\(added == 1 ? "" : "s") (sign in to them in Servers)" }
            message += "."
            if !result.skipped.isEmpty {
                message += "\n\nSkipped:\n" + result.skipped.map { "• \($0.key) — \($0.reason)" }.joined(separator: "\n")
            }
            report = message
        } catch {
            graph.messages.error((error as? LocalizedError)?.errorDescription ?? "That file could not be read.")
        }
    }
}

// ---------------------------------------------------------------- about --

private struct AboutSection: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingRow("Version", hint: "\(appVersion) (\(appBuild))")
        SettingRow("Source", hint: "github.com/evropiani/Kultr_iOS — issues and pull requests welcome.", action: { open(SOURCE) })
        SettingRow("Website", hint: "kultr.cc", action: { open(WEBSITE) })
        SettingRow("Get in touch", hint: "Questions, ideas, or something broken.", action: { open(DISCORD) }) {
            Pill("@evropiani", icon: "bubble.left.and.bubble.right.fill") { open(DISCORD) }
        }
    }

    private func open(_ link: String) {
        if let url = URL(string: link) { openURL(url) }
    }
}
