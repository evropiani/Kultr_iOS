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

@MainActor
private func setting<T>(_ read: @escaping (Settings) -> T, _ write: @escaping (inout Settings, T) -> Void) -> Binding<T> {
    Binding(
        get: { read(AppGraph.shared.settings.settings) },
        set: { value in update { write(&$0, value) } }
    )
}

private func bitrateLabel(_ value: Int) -> String {
    BITRATES.first { $0.0 == value }?.1 ?? "\(value) kbps"
}

private func signed(_ value: Double) -> String {
    let rounded = Int(value.rounded())
    return rounded > 0 ? "+\(rounded) dB" : "\(rounded) dB"
}

/**
 * Settings, the iOS way: a list of sections, each opening its own page of
 * switches, pickers and sliders.
 */
struct SettingsScreen: View {
    @Environment(\.kultr) private var theme

    var body: some View {
        let auth = AppGraph.shared.auth
        List {
            if let active = auth.active {
                Section {
                    NavigationLink {
                        ServerSettings()
                    } label: {
                        HStack(spacing: 14) {
                            Image("KultrLogo")
                                .resizable()
                                .frame(width: 54, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(active.label).font(.system(size: 19, weight: .semibold))
                                Text("\(active.username) · \(hostLabel(active.serverUrl))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            Section {
                link("Appearance", "paintpalette.fill", .pink) { AppearanceSettings() }
                link("Home page", "house.fill", .orange) { HomeSettings() }
            }
            Section {
                link("Playback", "play.fill", .red) { PlaybackSettings() }
                link("InjeKt", "sparkles", .purple) { InjektSettings() }
                link("Audio", "waveform", .blue) { AudioSettings() }
                link("Equaliser", "slider.vertical.3", .teal) { EqualiserSettings() }
            }
            Section {
                link("Offline and cache", "arrow.down.circle.fill", .green) { OfflineSettings() }
                // Signed in, the server card at the top already opens Servers.
                if auth.active == nil {
                    link("Servers", "server.rack", .indigo) { ServerSettings() }
                }
                link("Backup and reset", "externaldrive.fill", .gray) { BackupSettings() }
            }
            Section {
                link("About", "info.circle.fill", .gray) { AboutSection() }
            }
        }
        .navigationTitle("Settings")
        .settingsPage()
    }

    private func link<Destination: View>(_ title: String, _ icon: String, _ color: Color, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            SettingsIcon(title: title, icon: icon, color: color)
        }
    }
}

/** A row label in the style of the Settings app: a white symbol on a coloured tile. */
private struct SettingsIcon: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 29, height: 29)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color.gradient))
        }
    }
}

private extension View {
    /** A settings list over Kultr's background, tinted with the accent. */
    func settingsPage() -> some View {
        self
            .scrollContentBackground(.hidden)
            .kultrScreen()
    }
}

// ------------------------------------------------------------- controls --

/** A switch with a line of explanation under its label. */
private struct SettingToggle: View {
    let label: String
    let hint: String?
    let isOn: Binding<Bool>

    init(_ label: String, isOn: Binding<Bool>, hint: String? = nil) {
        self.label = label
        self.isOn = isOn
        self.hint = hint
    }

    var body: some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                if let hint {
                    Text(hint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/** A slider that keeps its own value while dragging and commits when released. */
private struct SettingSlider: View {
    @Environment(\.kultr) private var theme
    @Environment(\.isEnabled) private var isEnabled
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let format: (Double) -> String
    var hint: String?
    let onCommit: (Double) -> Void
    @State private var local: Double?

    var body: some View {
        let shown = local ?? value
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                Text(format(shown))
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(isEnabled ? theme.colors.accent : .secondary)
                    .contentTransition(.numericText())
            }
            Slider(
                value: Binding(get: { local ?? value }, set: { local = $0 }),
                in: range,
                step: step,
                onEditingChanged: { editing in
                    if editing {
                        Haptics.select()
                    } else if let committed = local {
                        onCommit(committed)
                        local = nil
                    }
                }
            )
            if let hint {
                Text(hint).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// ----------------------------------------------------------- appearance --

private struct AppearanceSettings: View {
    @Environment(\.kultr) private var theme

    var body: some View {
        let s = theme.settings
        let c = theme.colors
        Form {
            Section {
                Picker("Theme", selection: setting({ $0.theme }, { $0.theme = $1 })) {
                    Text("System").tag(ThemeMode.system)
                    Text("Light").tag(ThemeMode.light)
                    Text("Dark").tag(ThemeMode.dark)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                SettingToggle(
                    "Colour from artwork",
                    isOn: setting({ $0.accentMode == .artwork }, { $0.accentMode = $1 ? .artwork : .fixed }),
                    hint: "The interface takes its colour from whatever is playing."
                )
                VStack(alignment: .leading, spacing: 10) {
                    Text(s.accentMode == .artwork ? "Your colour" : "Accent colour")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(ACCENTS, id: \.self) { hex in
                                let selected = s.accent.lowercased() == hex
                                Button {
                                    Haptics.select()
                                    update { $0.accent = hex }
                                } label: {
                                    ZStack {
                                        Circle().fill(Color(argb: ArtworkColor.parseHex(hex) ?? 0))
                                        Circle().strokeBorder(selected ? c.ink : Color.primary.opacity(0.12), lineWidth: selected ? 3 : 1)
                                        if selected {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundStyle(.black.opacity(0.7))
                                        }
                                    }
                                    .frame(width: 34, height: 34)
                                    .scaleEffect(selected && !theme.reduceMotion ? 1.08 : 1)
                                    .animation(theme.spring, value: selected)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Accent \(hex)")
                                .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                if s.accentMode == .artwork {
                    SettingSlider(
                        label: "How much of your colour",
                        value: Double(s.accentBlend),
                        range: 0...100,
                        format: { "\(Int($0))%" },
                        hint: "0% is pure artwork colour; 100% ignores the artwork."
                    ) { v in update { $0.accentBlend = Int(v) } }
                }
            }
            Section("Surfaces") {
                SettingToggle("Blurred artwork background", isOn: setting({ $0.backdropArtwork }, { $0.backdropArtwork = $1 }))
                Picker("Corners", selection: setting({ $0.corners }, { $0.corners = $1 })) {
                    Text("Sharp").tag(CornerStyle.sharp)
                    Text("Soft").tag(CornerStyle.soft)
                    Text("Round").tag(CornerStyle.round)
                }
                Picker("Panel borders", selection: setting({ $0.surfaceBorder }, { $0.surfaceBorder = $1 })) {
                    Text("Neutral").tag(SurfaceBorder.neutral)
                    Text("Accent").tag(SurfaceBorder.accent)
                }
                SettingSlider(label: "Border opacity", value: Double(s.borderOpacity), range: 0...100, format: { "\(Int($0))%" }) { v in
                    update { $0.borderOpacity = Int(v) }
                }
                SettingSlider(label: "Panel opacity", value: Double(s.surfaceOpacity), range: 0...200, format: { "\(Int($0))%" }) { v in
                    update { $0.surfaceOpacity = Int(v) }
                }
            }
            Section("Lists") {
                Picker("Grid size", selection: setting({ $0.gridSize }, { $0.gridSize = $1 })) {
                    Text("Small").tag(GridSize.small)
                    Text("Medium").tag(GridSize.medium)
                    Text("Large").tag(GridSize.large)
                }
                SettingToggle("Compact track rows", isOn: setting({ $0.compactRows }, { $0.compactRows = $1 }))
            }
            Section {
                Picker("Playhead", selection: setting({ $0.playhead }, { $0.playhead = $1 })) {
                    ForEach(PlayheadStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                SettingToggle(
                    "Count time down",
                    isOn: setting({ $0.timeRemaining }, { $0.timeRemaining = $1 }),
                    hint: "Show how much of the track is left. Tapping the time in the player switches it too."
                )
                SettingToggle("Show the lyrics tab", isOn: setting({ $0.showLyrics }, { $0.showLyrics = $1 }))
            } header: {
                Text("Player")
            } footer: {
                Text(s.playhead.note)
            }
            Section {
                SettingToggle(
                    "Reduce motion",
                    isOn: setting({ $0.reduceMotion }, { $0.reduceMotion = $1 }),
                    hint: "Stops animated colour changes, sliding highlights and playhead effects. Kultr also follows Reduce Motion in iOS's Accessibility settings."
                )
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .settingsPage()
    }
}

// ------------------------------------------------------------ home page --

private struct HomeSettings: View {
    @Environment(\.kultr) private var theme

    var body: some View {
        let s = theme.settings
        let on = resolveHomeTiles(s.homeTiles)
        let off = availableHomeTiles(s.homeTiles)
        List {
            Section {
                ForEach(on) { tile in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tile.title)
                        Text(tile.note).font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .onMove { from, to in
                    var ids = on.map { $0.id }
                    ids.move(fromOffsets: from, toOffset: to)
                    Haptics.select()
                    update { $0.homeTiles = ids }
                }
                .onDelete { offsets in
                    var ids = on.map { $0.id }
                    ids.remove(atOffsets: offsets)
                    update { $0.homeTiles = ids }
                }
            } header: {
                Text("On the home page")
            } footer: {
                Text("Shelves are shown in this order; drag to move one, tap the red button to take it off. One with nothing in it is skipped.")
            }
            if !off.isEmpty {
                Section("Add a shelf") {
                    ForEach(off) { tile in
                        Button {
                            Haptics.tap()
                            update { $0.homeTiles = on.map { $0.id } + [tile.id] }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tile.title).foregroundStyle(Color.primary)
                                    Text(tile.note).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .animation(theme.spring, value: s.homeTiles)
        .navigationTitle("Home page")
        .navigationBarTitleDisplayMode(.inline)
        .settingsPage()
    }
}

// ------------------------------------------------------------- playback --

private struct PlaybackSettings: View {
    @Environment(\.kultr) private var theme

    var body: some View {
        let s = theme.settings
        Form {
            Section {
                SettingToggle(
                    "Crossfade between tracks",
                    isOn: setting({ $0.crossfadeEnabled }, { $0.crossfadeEnabled = $1 }),
                    hint: "Two decks play at once for the length of the fade."
                )
                SettingSlider(label: "Crossfade length", value: s.crossfadeSeconds, range: 1...20, format: { "\(Int($0)) s" }) { v in
                    update { $0.crossfadeSeconds = v.rounded() }
                }
                .disabled(!s.crossfadeEnabled)
                Picker("Fade shape", selection: setting({ $0.crossfadeCurve }, { $0.crossfadeCurve = $1 })) {
                    ForEach(CrossfadeCurve.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .disabled(!s.crossfadeEnabled)
                SettingToggle(
                    "Also fade when you skip",
                    isOn: setting({ $0.crossfadeOnSkip }, { $0.crossfadeOnSkip = $1 }),
                    hint: "A short fade instead of a hard cut on next and previous."
                )
                SettingToggle(
                    "Gapless playback",
                    isOn: setting({ $0.gapless }, { $0.gapless = $1 }),
                    hint: "With crossfade off, the next track starts the instant this one ends."
                )
            }
            Section {
                SettingToggle(
                    "Resume where you left off",
                    isOn: setting({ $0.resumeOnStart }, { $0.resumeOnStart = $1 }),
                    hint: "Restores the queue and position when Kultr opens. Pressing play on headphones or in Control Center picks it up too."
                )
                SettingToggle(
                    "Send plays to Navidrome",
                    isOn: setting({ $0.scrobble }, { $0.scrobble = $1 }),
                    hint: "Counts each play on your server, so recently and most played are the same on every device and survive reinstalling. Plays made offline are sent, with their real time, once you are back."
                )
            }
        }
        .navigationTitle("Playback")
        .navigationBarTitleDisplayMode(.inline)
        .settingsPage()
    }
}

// --------------------------------------------------------------- injekt --

private struct InjektSettings: View {
    @Environment(\.kultr) private var theme

    var body: some View {
        let s = theme.settings
        let on = s.injektEnabled
        Form {
            Section {
                SettingToggle(
                    "Enable InjeKt",
                    isOn: setting({ $0.injektEnabled }, { $0.injektEnabled = $1 }),
                    hint: "Beat-matched, key-aware transitions planned from each track's tempo, key and structure."
                )
            }
            Section("Blending") {
                SettingToggle(
                    "Beat-match",
                    isOn: setting({ $0.injektBeatMatch }, { $0.injektBeatMatch = $1 }),
                    hint: "Bring both tracks to a shared tempo and line up their bars."
                )
                SettingToggle(
                    "Meet in the middle",
                    isOn: setting({ $0.injektTempoRamp }, { $0.injektTempoRamp = $1 }),
                    hint: "Ease the current track toward the next one's tempo before the blend."
                )
                SettingSlider(
                    label: "Tempo share",
                    value: s.injektTempoBlend,
                    range: 0...100,
                    format: { "\(Int($0))%" },
                    hint: "How much of the tempo change the outgoing track makes."
                ) { v in update { $0.injektTempoBlend = v.rounded() } }
                .disabled(!s.injektTempoRamp)
                SettingSlider(
                    label: "Maximum tempo shift",
                    value: s.injektMaxTempoShift,
                    range: 2...16,
                    format: { "\(Int($0))%" },
                    hint: "Per track. Further apart than this, tracks are crossfaded instead."
                ) { v in update { $0.injektMaxTempoShift = v.rounded() } }
                Picker("Transition length", selection: setting({ $0.injektBars }, { $0.injektBars = $1 })) {
                    Text("4 bars").tag(4)
                    Text("8 bars").tag(8)
                    Text("16 bars").tag(16)
                    Text("32 bars").tag(32)
                }
                SettingToggle(
                    "Bass swap",
                    isOn: setting({ $0.injektBassSwap }, { $0.injektBassSwap = $1 }),
                    hint: "Roll the outgoing bass off before the incoming bass comes up."
                )
                SettingToggle(
                    "Harmonic mixing",
                    isOn: setting({ $0.injektHarmonic }, { $0.injektHarmonic = $1 }),
                    hint: "When keys clash, filter out of the old track instead of blending."
                )
                SettingToggle(
                    "Skip long intros",
                    isOn: setting({ $0.injektSkipIntro }, { $0.injektSkipIntro = $1 }),
                    hint: "Bring the next track in at its first real downbeat."
                )
            }
            .disabled(!on)
            Section {
                SettingToggle(
                    "Keep playing similar music",
                    isOn: setting({ $0.injektAutoQueue }, { $0.injektAutoQueue = $1 }),
                    hint: "When the queue runs out, continue with tracks chosen by tempo, key and energy."
                )
            }
            Section("Analysis") {
                SettingToggle(
                    "Analyse ahead",
                    isOn: setting({ $0.injektAnalyseAhead }, { $0.injektAnalyseAhead = $1 }),
                    hint: "The current and next track are always analysed when a track starts. This also measures the one after, so skipping ahead lands on a transition that is ready too."
                )
                SettingToggle(
                    "Analyse on Wi-Fi only",
                    isOn: setting({ $0.injektAnalyseOnWifiOnly }, { $0.injektAnalyseOnWifiOnly = $1 }),
                    hint: "Never spend mobile data on analysis."
                )
            }
            .disabled(!on)
        }
        .navigationTitle("InjeKt")
        .navigationBarTitleDisplayMode(.inline)
        .settingsPage()
    }
}

// ---------------------------------------------------------------- audio --

private struct AudioSettings: View {
    @Environment(\.kultr) private var theme

    var body: some View {
        let s = theme.settings
        Form {
            Section("Volume") {
                Picker("Volume levelling", selection: setting({ $0.replayGainMode }, { $0.replayGainMode = $1 })) {
                    ForEach(ReplayGainMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                SettingSlider(label: "ReplayGain pre-amp", value: s.replayGainPreamp, range: -12...12, format: signed) { v in
                    update { $0.replayGainPreamp = v.rounded() }
                }
                .disabled(s.replayGainMode == .off)
            }
            Section {
                Picker("On Wi-Fi", selection: setting({ $0.preferredBitrate }, { $0.preferredBitrate = $1 })) {
                    ForEach(BITRATES.map { $0.0 }, id: \.self) { value in Text(bitrateLabel(value)).tag(value) }
                }
                Picker("On mobile data", selection: setting({ $0.preferredBitrateMobile }, { $0.preferredBitrateMobile = $1 })) {
                    Text("Same as Wi-Fi").tag(-1)
                    ForEach(BITRATES.map { $0.0 }, id: \.self) { value in Text(bitrateLabel(value)).tag(value) }
                }
                Picker("Transcode format", selection: setting({ ["", "mp3", "aac"].contains($0.preferredFormat) ? $0.preferredFormat : "" }, { $0.preferredFormat = $1 })) {
                    Text("Server default").tag("")
                    Text("MP3").tag("mp3")
                    Text("AAC").tag("aac")
                }
            } header: {
                Text("Streaming quality")
            } footer: {
                Text("Lower bitrates are transcoded by your server, in the format chosen here. iPhones cannot play Opus or Vorbis streams, so those are not offered.")
            }
        }
        .navigationTitle("Audio")
        .navigationBarTitleDisplayMode(.inline)
        .settingsPage()
    }
}

// ------------------------------------------------------------ equaliser --

private struct EqualiserSettings: View {
    @Environment(\.kultr) private var theme

    var body: some View {
        let s = theme.settings
        let gains = s.eqBandGains
        Form {
            Section {
                SettingToggle("Enable the equaliser", isOn: setting({ $0.eqEnabled }, { $0.eqEnabled = $1 }))
                Picker("Preset", selection: Binding(
                    get: { s.eqPreset },
                    set: { name in AppGraph.shared.settings.replace(AppGraph.shared.settings.current.withEqPreset(name)) }
                )) {
                    ForEach(EQ_PRESET_LIST.map { $0.name }, id: \.self) { Text($0).tag($0) }
                    if EQ_PRESETS[s.eqPreset] == nil { Text(s.eqPreset).tag(s.eqPreset) }
                }
                .disabled(!s.eqEnabled)
            }
            Section {
                EqCurve(gains: gains)
                    .frame(height: 90)
                    .listRowBackground(Color.clear)
                ForEach(Array(EQ_BANDS.enumerated()), id: \.offset) { index, hz in
                    SettingSlider(
                        label: hz >= 1000 ? "\(hz / 1000) kHz" : "\(hz) Hz",
                        value: gains[index],
                        range: -12...12,
                        format: signed
                    ) { v in
                        update { st in
                            var next = st.eqBandGains
                            next[index] = v.rounded()
                            st.eqGains = next
                            st.eqPreset = "Custom"
                        }
                    }
                }
                SettingSlider(
                    label: "Pre-amp",
                    value: s.eqPreamp,
                    range: -12...6,
                    format: signed,
                    hint: "Pull this down if the equaliser makes things clip."
                ) { v in update { $0.eqPreamp = v.rounded() } }
            }
            .disabled(!s.eqEnabled)
        }
        .navigationTitle("Equaliser")
        .navigationBarTitleDisplayMode(.inline)
        .settingsPage()
    }
}

/** The ten bands as a smooth curve, so the shape of a preset is visible at a glance. */
private struct EqCurve: View {
    @Environment(\.kultr) private var theme
    let gains: [Double]

    var body: some View {
        let c = theme.colors
        Canvas { context, size in
            let mid = size.height / 2
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: mid))
            baseline.addLine(to: CGPoint(x: size.width, y: mid))
            context.stroke(baseline, with: .color(c.ink4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            guard gains.count > 1 else { return }
            let points = gains.enumerated().map { index, gain in
                CGPoint(
                    x: size.width * CGFloat(index) / CGFloat(gains.count - 1),
                    y: mid - CGFloat(gain / 12) * (size.height / 2 - 6)
                )
            }
            var curve = Path()
            curve.move(to: points[0])
            for i in 1..<points.count {
                let a = points[i - 1]
                let b = points[i]
                let midX = (a.x + b.x) / 2
                curve.addCurve(to: b, control1: CGPoint(x: midX, y: a.y), control2: CGPoint(x: midX, y: b.y))
            }
            var fill = curve
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            context.fill(fill, with: .linearGradient(Gradient(colors: [c.accent.opacity(0.35), .clear]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(curve, with: .color(c.accent), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

// -------------------------------------------------------------- offline --

private struct OfflineSettings: View {
    @Environment(\.kultr) private var theme
    @State private var cleared = false

    var body: some View {
        let s = theme.settings
        let graph = AppGraph.shared
        Form {
            Section {
                SettingSlider(label: "Parallel downloads", value: Double(s.offlineConcurrency), range: 1...8, format: { "\(Int($0))" }) { v in
                    update { $0.offlineConcurrency = Int(v) }
                }
                Picker("Download quality", selection: setting({ $0.offlineBitrate }, { $0.offlineBitrate = $1 })) {
                    ForEach(BITRATES.map { $0.0 }, id: \.self) { value in Text(bitrateLabel(value)).tag(value) }
                }
                SettingToggle("Download on Wi-Fi only", isOn: setting({ $0.offlineWifiOnly }, { $0.offlineWifiOnly = $1 }))
                SettingToggle(
                    "Prefer offline copies",
                    isOn: setting({ $0.offlineFirst }, { $0.offlineFirst = $1 }),
                    hint: "Play a downloaded file instead of streaming when one exists."
                )
                Button("Open Downloads") { graph.actions.openDownloads(.offline) }
            } header: {
                Text("Downloads")
            } footer: {
                Text("Original keeps the file exactly as it is on the server.")
            }
            Section {
                Picker("Stream cache", selection: setting({ $0.streamCacheMb }, { $0.streamCacheMb = $1 })) {
                    Text("256 MB").tag(256)
                    Text("1 GB").tag(1024)
                    Text("2 GB").tag(2048)
                    Text("4 GB").tag(4096)
                    Text("8 GB").tag(8192)
                }
                Button(cleared ? "Stream cache cleared" : "Clear stream cache") {
                    graph.clearMediaCache()
                    Haptics.success()
                    withAnimation(theme.ease) { cleared = true }
                }
                .disabled(cleared)
            } header: {
                Text("Streaming")
            } footer: {
                Text("Recently streamed audio is kept so replays do not refetch.")
            }
        }
        .navigationTitle("Offline and cache")
        .navigationBarTitleDisplayMode(.inline)
        .settingsPage()
    }
}

// -------------------------------------------------------------- servers --

private struct ServerSettings: View {
    @Environment(\.kultr) private var theme
    @State private var forget: ServerProfile?
    @State private var renaming: ServerProfile?
    @State private var newName = ""

    var body: some View {
        let graph = AppGraph.shared
        let auth = graph.auth
        let c = theme.colors
        let activeId = auth.active?.id
        List {
            Section {
                ForEach(auth.profiles) { profile in
                    let isActive = profile.id == activeId
                    HStack(spacing: 12) {
                        Image(systemName: isActive ? "checkmark.circle.fill" : "server.rack")
                            .font(.system(size: 18))
                            .foregroundStyle(isActive ? c.accent : .secondary)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.label)
                                .font(.body.weight(isActive ? .semibold : .regular))
                                .lineLimit(1)
                            Text([profile.username.isEmpty ? "not signed in" : profile.username, profile.serverUrl].joined(separator: " · "))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if !profile.hasCredentials {
                            Button("Sign in") { graph.ui.login = LoginRequest(url: profile.serverUrl, user: profile.username) }
                                .buttonStyle(.borderless)
                        } else if !isActive && profile.enabled {
                            Button("Use") { _ = auth.switchTo(profile.id) }
                                .buttonStyle(.borderless)
                        }
                        Toggle("Enabled", isOn: Binding(get: { profile.enabled }, set: { auth.setEnabled(profile.id, $0) }))
                            .labelsHidden()
                    }
                    .opacity(profile.enabled ? 1 : 0.55)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { forget = profile } label: { Label("Forget", systemImage: "trash") }
                        Button { rename(profile) } label: { Label("Rename", systemImage: "pencil") }
                            .tint(.orange)
                    }
                    .contextMenu {
                        Button { rename(profile) } label: { Label("Rename", systemImage: "pencil") }
                        Button(role: .destructive) { forget = profile } label: { Label("Forget \(profile.label)", systemImage: "trash") }
                    }
                }
            } footer: {
                Text("Swipe a server or touch and hold it to rename or forget it. A server that is switched off keeps its password and library but cannot be connected to.")
            }
            Section {
                Button { graph.ui.login = LoginRequest() } label: { Label("Add a server", systemImage: "plus") }
                if auth.active != nil {
                    Button(role: .destructive) {
                        graph.player.stop()
                        auth.signOut()
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
        }
        .navigationTitle("Servers")
        .navigationBarTitleDisplayMode(.inline)
        .settingsPage()
        .alert(
            "Rename server",
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
            presenting: renaming
        ) { profile in
            TextField(hostLabel(profile.serverUrl), text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { auth.rename(profile.id, to: newName) }
        } message: { profile in
            Text("A name for \(hostLabel(profile.serverUrl)). Leave it empty to use the address.")
        }
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

extension ServerSettings {
    fileprivate func rename(_ profile: ServerProfile) {
        newName = profile.label
        renaming = profile
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
        Form {
            Section {
                SettingToggle("Include the list of servers", isOn: $includeServers, hint: "Addresses only — never usernames or passwords.")
                Button {
                    let servers = includeServers
                        ? graph.auth.profiles.map { SettingsFile.ExportedServer(label: $0.label, serverUrl: $0.serverUrl, authMode: $0.authMode) }
                        : nil
                    document = JsonDocument(
                        text: SettingsFile.export(graph.settings.current, appVersion: appVersion, exportedAt: ISO8601DateFormatter().string(from: Date()), servers: servers)
                    )
                    exporting = true
                } label: {
                    Label("Export settings", systemImage: "square.and.arrow.up")
                }
                Button { importing = true } label: { Label("Import settings", systemImage: "square.and.arrow.down") }
            } header: {
                Text("Backup")
            } footer: {
                Text("Export every preference to a small file and import it on another phone, or in Kultr on the web or Android. Passwords and usernames are never in it.")
            }
            Section {
                Button(role: .destructive) { confirmReset = true } label: { Label("Reset settings", systemImage: "arrow.counterclockwise") }
                Button(role: .destructive) { confirmWipe = true } label: { Label("Clear library data", systemImage: "trash") }
            } header: {
                Text("Reset")
            }
        }
        .navigationTitle("Backup and reset")
        .navigationBarTitleDisplayMode(.inline)
        .settingsPage()
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
        Form {
            Section {
                VStack(spacing: 10) {
                    Image("KultrLogo")
                        .resizable()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                    Text("Kultr").font(.title2.weight(.bold))
                    Text("Version \(appVersion) (\(appBuild))").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }
            Section {
                link("Source code", "chevron.left.forwardslash.chevron.right", "github.com/evropiani/Kultr_iOS", SOURCE)
                link("Website", "globe", "kultr.cc", WEBSITE)
                link("Get in touch", "bubble.left.and.bubble.right.fill", "Questions, ideas, or something broken: @evropiani on Discord", DISCORD)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .settingsPage()
    }

    private func link(_ title: String, _ icon: String, _ detail: String, _ address: String) -> some View {
        Button {
            if let url = URL(string: address) { openURL(url) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 26).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Color.primary)
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
    }
}
