import SwiftUI

/**
 * Widgets at the top of Home, arranged like the iPhone's home screen: small
 * ones side by side, medium and large ones across. Hold one to edit: they
 * wiggle, the minus takes one away, drag one onto another to move it, and
 * "Add a widget" offers the rest.
 */
struct HomeWidgetsGrid: View {
    @Environment(\.kultr) private var theme
    @State private var editing = false
    @State private var adding = false

    var body: some View {
        let graph = AppGraph.shared
        let widgets = theme.settings.homeWidgets
        VStack(spacing: 12) {
            ForEach(Array(homeWidgetRows(widgets).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { index in
                        tile(widgets[index])
                    }
                    if row.count == 1 && widgets[row[0]].size == .small {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            }
            if editing || widgets.isEmpty {
                HStack(spacing: 8) {
                    Pill("Add a widget", icon: "plus") { adding = true }
                    Spacer()
                    if editing {
                        Pill("Done", accent: true) { withAnimation(theme.ease) { editing = false } }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .sheet(isPresented: $adding) {
            AddWidgetSheet { widget in
                graph.settings.update { $0.homeWidgets.append(widget) }
                adding = false
            } onCancel: {
                adding = false
            }
            .environment(\.kultr, theme)
        }
    }

    @ViewBuilder
    private func tile(_ widget: HomeWidget) -> some View {
        let graph = AppGraph.shared
        let c = theme.colors
        let content = HomeWidgetView(widget: widget, editing: editing)
            .frame(maxWidth: .infinity)
            .frame(height: widget.size == .large ? 312 : 150)
            .background(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous).fill(c.sand))
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous))
            .modifier(Wiggle(on: editing && !theme.reduceMotion))
            .overlay(alignment: .topLeading) {
                if editing {
                    Button {
                        withAnimation(theme.ease) { graph.settings.update { $0.homeWidgets.removeAll { $0.id == widget.id } } }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(c.ink)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(c.elevated))
                            .overlay(Circle().strokeBorder(c.ink4, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .offset(x: -8, y: -8)
                    .accessibilityLabel("Remove \(widget.kind.label)")
                }
            }
            .dropDestination(for: String.self) { ids, _ in
                guard editing, let moving = ids.first, moving != widget.id else { return false }
                withAnimation(theme.ease) { move(moving, before: widget.id) }
                return true
            }
            .accessibilityAction(named: "Edit widgets") { editing = true }
        if editing {
            content.draggable(widget.id) {
                Image(systemName: widget.kind.icon)
                    .font(.largeTitle)
                    .foregroundStyle(c.accent)
                    .frame(width: 80, height: 80)
                    .background(RoundedRectangle(cornerRadius: 16).fill(c.sand))
            }
        } else {
            content.onLongPressGesture(minimumDuration: 0.5) {
                Haptics.tap()
                withAnimation(theme.ease) { editing = true }
            }
        }
    }

    private func move(_ id: String, before target: String) {
        AppGraph.shared.settings.update { s in
            guard let from = s.homeWidgets.firstIndex(where: { $0.id == id }) else { return }
            let widget = s.homeWidgets.remove(at: from)
            let to = s.homeWidgets.firstIndex(where: { $0.id == target }) ?? s.homeWidgets.count
            s.homeWidgets.insert(widget, at: to)
        }
    }
}

/** A small, endless wobble, like the home screen's while editing. */
private struct Wiggle: ViewModifier {
    let on: Bool
    @State private var tilt = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(on ? (tilt ? 1.2 : -1.2) : 0))
            .onChange(of: on, initial: true) { _, now in
                guard now else {
                    tilt = false
                    return
                }
                withAnimation(.easeInOut(duration: 0.13).repeatForever(autoreverses: true)) { tilt = true }
            }
    }
}

/** One widget's content. */
private struct HomeWidgetView: View {
    let widget: HomeWidget
    let editing: Bool

    var body: some View {
        Group {
            switch widget.kind {
            case .nowPlaying: NowPlayingTile(size: widget.size)
            case .listening: ListeningTile(size: widget.size)
            case .nextMix: NextMixTile(size: widget.size)
            case .station: StationTile(id: widget.ref, size: widget.size)
            case .crate: CrateTile(id: widget.ref, size: widget.size)
            case .shortcut: ShortcutTile(words: widget.ref ?? "", size: widget.size)
            }
        }
        .allowsHitTesting(!editing)
    }
}

// ----------------------------------------------------------------- tiles --

private struct TileLabel: View {
    @Environment(\.kultr) private var theme
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(KFont.labelSmall.weight(.semibold))
            .foregroundStyle(theme.colors.accent)
            .lineLimit(1)
    }
}

private struct NowPlayingTile: View {
    @Environment(\.kultr) private var theme
    let size: HomeWidget.Size

    var body: some View {
        let graph = AppGraph.shared
        let player = graph.player
        let c = theme.colors
        let state = player.state
        if let song = state.current {
            let playing = state.playWhenReady && !state.ended
            let controls = HStack(spacing: size == .small ? 12 : 22) {
                if size != .small {
                    Button { player.previous() } label: { Image(systemName: "backward.end.fill") }
                        .accessibilityLabel("Previous")
                }
                Button { player.toggle() } label: { Image(systemName: playing ? "pause.fill" : "play.fill").font(.title2) }
                    .accessibilityLabel(playing ? "Pause" : "Play")
                Button { player.next() } label: { Image(systemName: "forward.end.fill") }
                    .accessibilityLabel("Next")
            }
            .buttonStyle(PressScaleStyle())
            .foregroundStyle(c.ink)
            Button { graph.actions.openPlayer() } label: {
                Group {
                    switch size {
                    case .small:
                        VStack(alignment: .leading, spacing: 6) {
                            Artwork(coverId: song.artworkId, size: 64, label: song.title)
                            Spacer(minLength: 0)
                            Text(song.title).font(.subheadline.weight(.semibold)).foregroundStyle(c.ink).lineLimit(1)
                            Text(song.artist ?? "").font(.caption).foregroundStyle(c.ink3).lineLimit(1)
                        }
                    case .medium:
                        HStack(spacing: 12) {
                            Artwork(coverId: song.artworkId, size: 118, label: song.title)
                            VStack(alignment: .leading, spacing: 4) {
                                TileLabel(icon: "waveform", text: "Now playing")
                                Text(song.title).font(.headline).foregroundStyle(c.ink).lineLimit(2)
                                Text(song.artist ?? "").font(.subheadline).foregroundStyle(c.ink2).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            Spacer(minLength: 0)
                        }
                    case .large:
                        VStack(spacing: 10) {
                            Artwork(coverId: song.artworkId, size: 180, label: song.title)
                            Text(song.title).font(.headline).foregroundStyle(c.ink).lineLimit(1)
                            Text(song.artist ?? "").font(.subheadline).foregroundStyle(c.ink2).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: size == .large ? .bottom : .bottomTrailing) {
                controls.padding(12)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                TileLabel(icon: "waveform", text: "Now playing")
                Text("Nothing is playing").font(.headline).foregroundStyle(c.ink)
                Spacer(minLength: 0)
                Pill("Resume", icon: "play.fill", accent: true) { player.resume() }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct ListeningTile: View {
    @Environment(\.kultr) private var theme
    let size: HomeWidget.Size
    @State private var week: Int64 = 0
    @State private var usual: Int64 = 0
    @State private var days: [Int64] = []

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        Button { graph.actions.navigate(.stats) } label: {
            VStack(alignment: .leading, spacing: 6) {
                TileLabel(icon: "chart.bar.fill", text: "This week")
                Text(Format.duration(week))
                    .font(size == .small ? .title2.bold() : .title.bold())
                    .foregroundStyle(c.ink)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(usual > 0 ? "Usually \(Format.duration(usual))" : "Your usual shows after a week")
                    .font(.caption)
                    .foregroundStyle(c.ink3)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if size != .small, !days.isEmpty {
                    let peak = max(1, days.max() ?? 1)
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(Array(days.enumerated()), id: \.offset) { _, seconds in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(c.accent)
                                .frame(height: max(3, (size == .large ? 150 : 44) * CGFloat(Double(seconds) / Double(peak))))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: size == .large ? 150 : 44, alignment: .bottom)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task(id: graph.library.historyVersion) { await load() }
    }

    private func load() async {
        let history = await AppGraph.shared.library.history(5000)
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        guard let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return }
        let startMs = Int64(start.timeIntervalSince1970 * 1000)
        let weekMs: Int64 = 7 * 86_400_000
        var thisWeek: Int64 = 0
        var before: Int64 = 0
        var perDay = Array(repeating: Int64(0), count: 7)
        for entry in history {
            if entry.playedAt >= startMs {
                thisWeek += Int64(entry.seconds)
                let day = Int((entry.playedAt - startMs) / 86_400_000)
                if perDay.indices.contains(day) { perDay[day] += Int64(entry.seconds) }
            } else if entry.playedAt >= startMs - 4 * weekMs {
                before += Int64(entry.seconds)
            }
        }
        week = thisWeek
        usual = before / 4
        days = perDay
    }
}

private struct NextMixTile: View {
    @Environment(\.kultr) private var theme
    let size: HomeWidget.Size

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        let state = graph.player.state
        let next = state.upNext.first?.song
        let plan = graph.player.transition.fromSongId == state.current?.id ? graph.player.transition.upcoming : nil
        Button { graph.actions.openPlayer() } label: {
            VStack(alignment: .leading, spacing: 6) {
                TileLabel(icon: "arrow.triangle.merge", text: "Next mix")
                if let next {
                    Text(next.title).font(.headline).foregroundStyle(c.ink).lineLimit(2)
                    Text(next.artist ?? "").font(.caption).foregroundStyle(c.ink3).lineLimit(1)
                    Spacer(minLength: 0)
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        let position = Double(graph.player.positionMs()) / 1000
                        let rate = (plan?.outgoingRate ?? 1) > 0 ? (plan?.outgoingRate ?? 1) : 1
                        let fade = theme.settings.crossfadeEnabled ? theme.settings.crossfadeSeconds : 0
                        let start = plan?.startAt ?? (Double(state.durationMs) / 1000 - fade)
                        let left = max(0, (start - position) / rate)
                        Text(state.playWhenReady ? "in \(Format.time(left))" : "paused")
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(c.accent)
                    }
                } else {
                    Text("Nothing up next").font(.headline).foregroundStyle(c.ink)
                    Text(theme.settings.karousel ? "Karousel finds more as the track plays." : "Queue something, or turn on Karousel.")
                        .font(.caption)
                        .foregroundStyle(c.ink3)
                    Spacer(minLength: 0)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct StationTile: View {
    @Environment(\.kultr) private var theme
    let id: String?
    let size: HomeWidget.Size

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        let station = graph.stations.all.first { $0.id == id }
        let playing = station != nil && graph.player.station?.id == station?.id
        Button {
            if let station { Task { await graph.player.playStation(station) } } else { graph.actions.navigate(.stations) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: playing ? "speaker.wave.2.fill" : (station?.icon ?? "dial.medium"))
                    .font(size == .small ? .title2 : .largeTitle)
                    .foregroundStyle(c.accent)
                Spacer(minLength: 0)
                Text(station?.name ?? "Station gone").font(.headline).foregroundStyle(c.ink).lineLimit(1)
                Text(station.map { graph.stations.counts[$0.id].map { Format.count($0, "track") } ?? $0.summary } ?? "Tap to choose another")
                    .font(.caption)
                    .foregroundStyle(c.ink3)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(station.map { "Play the station \($0.name)" } ?? "Station gone")
    }
}

private struct CrateTile: View {
    @Environment(\.kultr) private var theme
    let id: String?
    let size: HomeWidget.Size
    @State private var covers: [String] = []

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        let crate = graph.crates.all.first { $0.id == id }
        Button {
            guard let crate else { return }
            Task {
                let songs = await graph.crates.songs(crate)
                if songs.isEmpty { graph.actions.openCrate(crate.id) } else { graph.actions.play(songs) }
            }
        } label: {
            HStack(spacing: 12) {
                if size != .small {
                    let grid = Array(covers.prefix(4))
                    LazyVGrid(columns: [GridItem(.fixed(58), spacing: 2), GridItem(.fixed(58), spacing: 2)], spacing: 2) {
                        ForEach(Array(grid.enumerated()), id: \.offset) { _, cover in
                            ArtworkFill(coverId: cover, radius: 0).frame(width: 58, height: 58).clipped()
                        }
                    }
                    .frame(width: 118, height: 118, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 6) {
                    TileLabel(icon: crate?.icon ?? "shippingbox", text: "Crate")
                    Spacer(minLength: 0)
                    Text(crate?.name ?? "Crate gone").font(.headline).foregroundStyle(c.ink).lineLimit(2)
                    Text(crate.map { $0.byRules ? ($0.rules?.summary ?? "") : $0.contents } ?? "It was deleted")
                        .font(.caption)
                        .foregroundStyle(c.ink3)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let crate { Button { graph.actions.openCrate(crate.id) } label: { Label("Open the crate", systemImage: "shippingbox") } }
        }
        .task(id: crate?.hashValue ?? 0) {
            guard let crate, size != .small else { return }
            var seen = Set<String>()
            covers = await graph.crates.songs(crate).compactMap { $0.coverArt ?? $0.albumId }.filter { seen.insert($0).inserted }
        }
    }
}

private struct ShortcutTile: View {
    @Environment(\.kultr) private var theme
    let words: String
    let size: HomeWidget.Size

    var body: some View {
        let c = theme.colors
        let command = CommandRunner.parse(words)
        let what = command.map(CommandRunner.describe) ?? (icon: "questionmark", text: "“\(words)”")
        Button {
            guard let command else {
                AppGraph.shared.messages.show("Kultr doesn't know how to do “\(words)” any more.")
                return
            }
            Haptics.tap()
            Task { await CommandRunner.run(command) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: what.icon)
                    .font(.title2)
                    .foregroundStyle(c.onAccent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(c.accent))
                Spacer(minLength: 0)
                Text(what.text).font(.headline).foregroundStyle(c.ink).lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// ------------------------------------------------------------ adding one --

private let SHORTCUTS = [
    "shuffle all", "plan an hour", "sleep in 30 minutes", "mix now", "open stations",
    "open downloads", "open recap", "open crates",
]

/** Which widget, how big, and for a station, crate or shortcut, which one. */
private struct AddWidgetSheet: View {
    @Environment(\.kultr) private var theme
    let onAdd: (HomeWidget) -> Void
    let onCancel: () -> Void
    @State private var kind: HomeWidget.Kind = .nowPlaying
    @State private var size: HomeWidget.Size = .small
    @State private var ref = ""

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        NavigationStack {
            Form {
                Section {
                    ForEach(HomeWidget.Kind.allCases, id: \.self) { option in
                        Button {
                            kind = option
                            ref = defaultRef(option)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: option.icon).foregroundStyle(c.accent).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label).foregroundStyle(c.ink)
                                    Text(option.note).font(KFont.bodySmall).foregroundStyle(c.ink3)
                                }
                                Spacer()
                                if kind == option { Image(systemName: "checkmark").foregroundStyle(c.accent) }
                            }
                        }
                        .accessibilityAddTraits(kind == option ? .isSelected : [])
                    }
                }
                Section("Size") {
                    Picker("Size", selection: $size) {
                        ForEach(HomeWidget.Size.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                switch kind {
                case .station:
                    Section("Which station") {
                        Picker("Station", selection: $ref) {
                            ForEach(graph.stations.all) { Text($0.name).tag($0.id) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                case .crate:
                    Section("Which crate") {
                        if graph.crates.all.isEmpty {
                            Text("No crates yet: make one in Library → Crates.").foregroundStyle(c.ink3)
                        }
                        Picker("Crate", selection: $ref) {
                            ForEach(graph.crates.all) { Text($0.name).tag($0.id) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                case .shortcut:
                    Section {
                        Picker("Shortcut", selection: $ref) {
                            ForEach(SHORTCUTS, id: \.self) { words in
                                Text(CommandRunner.parse(words).map { CommandRunner.describe($0).text } ?? words).tag(words)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                        TextField("Or your own words, as in Search", text: $ref)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } header: {
                        Text("Which shortcut")
                    } footer: {
                        Text(CommandRunner.parse(ref).map { "Does: " + CommandRunner.describe($0).text } ?? "Kultr doesn't understand those words yet.")
                    }
                default:
                    EmptyView()
                }
            }
            .scrollContentBackground(.hidden)
            .background(c.background)
            .navigationTitle("Add a widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(HomeWidget(kind: kind, size: size, ref: [.station, .crate, .shortcut].contains(kind) ? ref : nil))
                    }
                    .disabled(!canAdd)
                }
            }
        }
        .tint(c.accent)
    }

    private var canAdd: Bool {
        switch kind {
        case .station, .crate: return !ref.isEmpty
        case .shortcut: return CommandRunner.parse(ref) != nil
        default: return true
        }
    }

    private func defaultRef(_ kind: HomeWidget.Kind) -> String {
        let graph = AppGraph.shared
        switch kind {
        case .station: return graph.stations.all.first?.id ?? ""
        case .crate: return graph.crates.all.first?.id ?? ""
        case .shortcut: return SHORTCUTS[0]
        default: return ""
        }
    }
}
