import SwiftUI

/**
 * Stations: endless mixes from your own library. Turn the dial to choose one;
 * it clicks at each station. While a station plays, turning the dial mixes
 * into the new one. Below it, your stations to edit, and one per decade.
 */
struct StationsScreen: View {
    @Environment(\.kultr) private var theme
    @State private var selected = 0
    @State private var editing: StationDraft?
    @State private var resetting = false
    /** The dial's position the last time it settled, so a station playing only switches on a real turn. */
    @State private var settledId: String?

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        let stations = graph.stations.all
        let playing = graph.player.station
        let current = stations.indices.contains(selected) ? stations[selected] : stations.first
        ScrollView {
            VStack(spacing: 0) {
                if !stations.isEmpty {
                    StationDial(stations: stations, selected: $selected)
                        .frame(maxWidth: 320)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                }
                if let current {
                    VStack(spacing: 4) {
                        Text(current.summary)
                            .font(KFont.bodyMedium)
                            .foregroundStyle(c.ink2)
                            .multilineTextAlignment(.center)
                        Text(countText(current))
                            .font(KFont.bodySmall)
                            .foregroundStyle(c.ink3)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                    Group {
                        if playing?.id == current.id {
                            WideButton(title: "End \(current.name)", icon: "stop.fill", prominent: false) {
                                graph.player.endStation()
                                graph.messages.show("Station ended")
                            }
                        } else {
                            WideButton(
                                title: playing == nil ? "Play \(current.name)" : "Switch to \(current.name)",
                                icon: playing == nil ? "play.fill" : "arrow.triangle.merge",
                                prominent: true,
                                enabled: (graph.stations.counts[current.id] ?? 1) > 0
                            ) {
                                Task {
                                    if playing == nil { await graph.player.playStation(current) } else { await graph.player.switchStation(current) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    if current.needsAnalysis || (current.bpm.map { !$0.isOpen } ?? false) {
                        AnalysisNote()
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    }
                }

                SectionHeader("Your stations")
                ForEach(graph.settings.current.stations) { station in
                    StationRow(
                        station: station,
                        count: graph.stations.counts[station.id],
                        selected: current?.id == station.id,
                        playing: playing?.id == station.id,
                        onSelect: { select(station, in: stations) },
                        onEdit: { editing = StationDraft(station: station, isNew: false) },
                        onCopy: { editing = StationDraft(station: copy(of: station), isNew: true) },
                        onDelete: { graph.stations.delete(station) }
                    )
                }
                HStack(spacing: 8) {
                    Pill("New station", icon: "plus", accent: true) {
                        editing = StationDraft(station: Station(name: "New station", icon: "dot.radiowaves.left.and.right", bpm: Bounds(100, 120)), isNew: true)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                if !graph.stations.decades.isEmpty {
                    SectionHeader("Decades")
                    ForEach(graph.stations.decades) { station in
                        StationRow(
                            station: station,
                            count: graph.stations.counts[station.id],
                            selected: current?.id == station.id,
                            playing: playing?.id == station.id,
                            onSelect: { select(station, in: stations) },
                            onEdit: nil,
                            onCopy: { editing = StationDraft(station: copy(of: station), isNew: true) },
                            onDelete: nil
                        )
                    }
                    Text("A station for every decade with at least 20 tracks, from the years in your tags.")
                        .font(KFont.bodySmall)
                        .foregroundStyle(c.ink3)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
            }
            .padding(.bottom, 32)
        }
        .navigationTitle("Stations")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { resetting = true } label: { Label("Back to the starting stations", systemImage: "arrow.counterclockwise") }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
        .kultrScreen()
        .task(id: "\(graph.library.version):\(graph.library.analysisVersion):\(graph.settings.current.stations.hashValue)") {
            graph.stations.refresh()
        }
        .onAppear {
            // Open on the station playing, if there is one.
            if let playing, let at = stations.firstIndex(where: { $0.id == playing.id }) { selected = at }
            settledId = current?.id
        }
        .task(id: selected) {
            // Turning the dial while a station plays mixes into the new one, once it has settled.
            guard let current, current.id != settledId else { return }
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            settledId = current.id
            if let playing = graph.player.station, playing.id != current.id, (graph.stations.counts[current.id] ?? 1) > 0 {
                await graph.player.switchStation(current)
            }
        }
        .sheet(item: $editing) { draft in
            StationEditor(draft: draft) { saved in
                graph.stations.save(saved)
                editing = nil
                if let at = graph.stations.all.firstIndex(where: { $0.id == saved.id }) {
                    settledId = saved.id
                    selected = at
                }
            } onCancel: {
                editing = nil
            }
            .environment(\.kultr, theme)
        }
        .alert("Back to the starting stations?", isPresented: $resetting) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { graph.stations.resetToPresets() }
        } message: {
            Text("Your own stations and changes go; Warm Up, Night Drive, Peak Hour, Deep Focus, Wind Down, Unplayed gems and Favourites come back.")
        }
    }

    private func countText(_ station: Station) -> String {
        guard let count = AppGraph.shared.stations.counts[station.id] else { return "Counting tracks…" }
        return count == 0 ? "No tracks fit yet" : "\(Format.count(count, "track")) fit"
    }

    private func select(_ station: Station, in stations: [Station]) {
        guard let at = stations.firstIndex(where: { $0.id == station.id }) else { return }
        Haptics.select()
        selected = at
    }

    private func copy(of station: Station) -> Station {
        var copy = station
        copy.id = UUID().uuidString
        copy.name = station.name + " (copy)"
        return copy
    }
}

/** Some stations need InjeKt's analysis; say how far along it is, with a way to finish it. */
private struct AnalysisNote: View {
    @Environment(\.kultr) private var theme
    @State private var analysed = 0
    @State private var missing = 0

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        Group {
            if missing > 0 {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles").foregroundStyle(c.accent)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tempo, energy and key come from InjeKt's analysis, which has covered \(Format.count(analysed, "track")) so far, with \(Format.count(missing, "track")) to go. This station grows as more are analysed.")
                            .font(KFont.bodySmall)
                            .foregroundStyle(c.ink2)
                        if let progress = graph.analysis.bulkProgress {
                            Text("Analysing \(progress.done + 1) of \(progress.total)…")
                                .font(KFont.bodySmall.monospacedDigit())
                                .foregroundStyle(c.ink3)
                        } else {
                            Pill("Analyse the rest", icon: "sparkles") { graph.analysis.startBulk() }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(c.sand))
            }
        }
        .task(id: graph.library.analysisVersion) {
            analysed = await graph.analysis.analysedCount()
            missing = await graph.analysis.missingCount()
        }
    }
}

// --------------------------------------------------------------- the dial --

/**
 * A ring of glass with a station at each stop. Drag around it to turn; it
 * clicks as each station passes the pointer at the top and settles on the
 * nearest one when you let go.
 */
private struct StationDial: View {
    @Environment(\.kultr) private var theme
    let stations: [Station]
    @Binding var selected: Int
    /** Radians; station i sits under the pointer at -i × step. */
    @State private var angle: Double = 0
    @State private var lastTouch: Double?

    private var step: Double { 2 * .pi / Double(max(stations.count, 1)) }

    var body: some View {
        let c = theme.colors
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let iconRadius = size * 0.405
            ZStack {
                Color.clear
                    .frame(width: size, height: size)
                    .kultrGlass(Circle(), interactive: true)
                Circle()
                    .fill(c.background)
                    .frame(width: size * 0.62, height: size * 0.62)
                ForEach(Array(stations.enumerated()), id: \.element.id) { index, station in
                    let a = angle + Double(index) * step - .pi / 2
                    Image(systemName: station.icon)
                        .font(.system(size: size * 0.065, weight: .semibold))
                        .foregroundStyle(index == selected ? c.accent : c.ink3)
                        .scaleEffect(index == selected ? 1.25 : 1)
                        .position(x: center.x + cos(a) * iconRadius, y: center.y + sin(a) * iconRadius)
                }
                // The pointer at the top.
                Capsule()
                    .fill(c.accent)
                    .frame(width: 4, height: size * 0.06)
                    .position(x: center.x, y: center.y - size / 2 + size * 0.035)
                if stations.indices.contains(selected) {
                    VStack(spacing: 6) {
                        Image(systemName: stations[selected].icon)
                            .font(.system(size: size * 0.09, weight: .semibold))
                            .foregroundStyle(c.accent)
                        Text(stations[selected].name)
                            .font(.title2.bold())
                            .foregroundStyle(c.ink)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .multilineTextAlignment(.center)
                            .contentTransition(.opacity)
                    }
                    .frame(width: size * 0.5)
                    .position(center)
                    .allowsHitTesting(false)
                }
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        let touch = atan2(value.location.y - center.y, value.location.x - center.x)
                        if let lastTouch {
                            var delta = touch - lastTouch
                            if delta > .pi { delta -= 2 * .pi }
                            if delta < -.pi { delta += 2 * .pi }
                            angle += delta
                        }
                        lastTouch = touch
                        let index = nearestIndex
                        if index != selected {
                            selected = index
                            Haptics.select()
                        }
                    }
                    .onEnded { _ in
                        lastTouch = nil
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { angle = target(for: selected) }
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: selected) { _, index in
            // Chosen from the list: turn there.
            guard lastTouch == nil else { return }
            withAnimation(theme.spring ?? .default) { angle = target(for: index) }
        }
        .onChange(of: stations.count) { _, _ in angle = target(for: selected) }
        .onAppear { angle = target(for: selected) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Station dial")
        .accessibilityValue(stations.indices.contains(selected) ? stations[selected].name : "")
        .accessibilityAdjustableAction { direction in
            guard !stations.isEmpty else { return }
            switch direction {
            case .increment: selected = (selected + 1) % stations.count
            case .decrement: selected = (selected - 1 + stations.count) % stations.count
            @unknown default: break
            }
        }
    }

    private var nearestIndex: Int {
        guard !stations.isEmpty else { return 0 }
        let raw = Int((-angle / step).rounded())
        let n = stations.count
        return ((raw % n) + n) % n
    }

    /** The angle that puts station [index] under the pointer, the shortest way round from here. */
    private func target(for index: Int) -> Double {
        let base = -Double(index) * step
        let turns = ((angle - base) / (2 * .pi)).rounded()
        return base + turns * 2 * .pi
    }
}

// --------------------------------------------------------------- the rows --

private struct StationRow: View {
    @Environment(\.kultr) private var theme
    let station: Station
    let count: Int?
    let selected: Bool
    let playing: Bool
    let onSelect: () -> Void
    let onEdit: (() -> Void)?
    let onCopy: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        let c = theme.colors
        HStack(spacing: 12) {
            Image(systemName: playing ? "speaker.wave.2.fill" : station.icon)
                .font(.title3)
                .foregroundStyle(c.accent)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? c.accentSoft : c.sand))
            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                    .font(KFont.bodyLarge.weight(selected ? .semibold : .regular))
                    .foregroundStyle(c.ink)
                    .lineLimit(1)
                Text([station.summary, count.map { Format.count($0, "track") }].compactMap { $0 }.joined(separator: " · "))
                    .font(KFont.bodySmall)
                    .foregroundStyle(c.ink3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                if let onEdit { Button(action: onEdit) { Label("Edit…", systemImage: "slider.horizontal.3") } }
                Button(action: onCopy) { Label(onEdit == nil ? "Make a copy to edit…" : "Duplicate…", systemImage: "plus.square.on.square") }
                if let onDelete { Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") } }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(c.accent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More for \(station.name)")
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/** A station on the Home shelf: tap to play it. */
struct MixStationCard: View {
    @Environment(\.kultr) private var theme
    let station: Station

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        let playing = graph.player.station?.id == station.id
        Button {
            Task { await graph.player.playStation(station) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: playing ? "speaker.wave.2.fill" : station.icon)
                    .font(.title2)
                    .foregroundStyle(c.accent)
                Spacer(minLength: 0)
                Text(station.name)
                    .font(.headline)
                    .foregroundStyle(c.ink)
                    .lineLimit(1)
                Text(graph.stations.counts[station.id].map { Format.count($0, "track") } ?? station.summary)
                    .font(KFont.bodySmall)
                    .foregroundStyle(c.ink3)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(width: 150, height: 120, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous).fill(playing ? c.accentSoft : c.sand))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .contextMenu {
            Button { graph.actions.navigate(.stations) } label: { Label("Open Stations", systemImage: "dial.medium") }
        }
        .accessibilityLabel("Play the station \(station.name)")
    }
}

// ------------------------------------------------------------- the editor --

struct StationDraft: Identifiable {
    var station: Station
    let isNew: Bool
    var id: String { station.id }
}

private let STATION_ICONS = [
    "dot.radiowaves.left.and.right", "sunrise.fill", "car.fill", "flame.fill", "brain.head.profile", "moon.stars.fill",
    "sparkle", "heart.fill", "figure.run", "cup.and.saucer.fill", "leaf.fill", "bolt.fill", "headphones", "guitars.fill",
    "pianokeys", "music.mic", "sun.max.fill", "cloud.rain.fill", "snowflake", "party.popper.fill",
]

private let CAMELOT_KEYS: [String] = (1...12).flatMap { ["\($0)A", "\($0)B"] }

/** Every rule of a station, with how many tracks fit as you change them. */
private struct StationEditor: View {
    @Environment(\.kultr) private var theme
    @State private var station: Station
    @State private var count: Int?
    @State private var genres: [String] = []
    let isNew: Bool
    let onSave: (Station) -> Void
    let onCancel: () -> Void

    init(draft: StationDraft, onSave: @escaping (Station) -> Void, onCancel: @escaping () -> Void) {
        _station = State(initialValue: draft.station)
        isNew = draft.isNew
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        let c = theme.colors
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $station.name)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(STATION_ICONS, id: \.self) { icon in
                                Button { station.icon = icon } label: {
                                    Image(systemName: icon)
                                        .font(.title3)
                                        .foregroundStyle(station.icon == icon ? c.onAccent : c.accent)
                                        .frame(width: 44, height: 44)
                                        .background(Circle().fill(station.icon == icon ? c.accent : c.sand))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(icon)
                                .accessibilityAddTraits(station.icon == icon ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    BoundsEditor(label: "Tempo", bounds: $station.bpm, range: 50...200, step: 2, initial: Bounds(100, 120)) { "\(Int($0)) BPM" }
                } footer: {
                    Text("From InjeKt's analysis, or the tempo in the track's tags.")
                }
                Section {
                    BoundsEditor(label: "Energy", bounds: energy, range: 1...10, step: 1, initial: Bounds(3, 7)) { String(Int($0)) }
                } footer: {
                    Text("1 is a quiet acoustic track, 10 a loud club track. Needs InjeKt's analysis.")
                }
                Section {
                    Toggle("Any key", isOn: Binding(get: { (station.keys ?? []).isEmpty }, set: { station.keys = $0 ? nil : ["8A"] }))
                        .tint(c.accent)
                    if !(station.keys ?? []).isEmpty {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                            ForEach(CAMELOT_KEYS, id: \.self) { key in
                                let on = station.keys?.contains(key) ?? false
                                Button {
                                    var keys = station.keys ?? []
                                    if on { keys.removeAll { $0 == key } } else { keys.append(key) }
                                    station.keys = keys.isEmpty ? nil : keys
                                } label: {
                                    Text(key)
                                        .font(KFont.bodySmall.weight(.semibold))
                                        .foregroundStyle(on ? c.onAccent : c.ink2)
                                        .frame(maxWidth: .infinity, minHeight: 32)
                                        .background(Capsule().fill(on ? c.accent : c.sand))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Key")
                } footer: {
                    Text("Camelot keys: neighbours on the wheel mix well. Needs InjeKt's analysis.")
                }
                Section("Genres") {
                    NavigationLink {
                        GenrePicker(all: genres, chosen: Binding(get: { station.genres ?? [] }, set: { station.genres = $0.isEmpty ? nil : $0 }))
                            .environment(\.kultr, theme)
                    } label: {
                        HStack {
                            Text("Genres")
                            Spacer()
                            Text((station.genres ?? []).isEmpty ? "Any" : (station.genres ?? []).joined(separator: ", "))
                                .foregroundStyle(c.ink3)
                                .lineLimit(1)
                        }
                    }
                }
                Section {
                    BoundsEditor(label: "Years", bounds: $station.years, range: 1950...Double(Calendar.current.component(.year, from: Date())), step: 1, initial: Bounds(2000, 2009)) { String(Int($0)) }
                }
                Section {
                    Toggle("Only tracks never played", isOn: $station.unplayed).tint(c.accent)
                    Toggle("Only favourites", isOn: $station.favourites).tint(c.accent)
                    Picker("Rating", selection: Binding(get: { station.minRating ?? 0 }, set: { station.minRating = $0 == 0 ? nil : $0 })) {
                        Text("Any").tag(0)
                        ForEach(1...5, id: \.self) { Text("\($0)★ and up").tag($0) }
                    }
                } footer: {
                    Text(count.map { $0 == 0 ? "No tracks fit these rules yet." : "\(Format.count($0, "track")) fit these rules." } ?? "Counting…")
                        .font(KFont.bodyMedium.weight(.semibold))
                        .foregroundStyle(c.accent)
                }
            }
            .scrollContentBackground(.hidden)
            .background(c.background)
            .navigationTitle(isNew ? "New station" : "Edit station")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var saved = station
                        saved.name = saved.name.trimmingCharacters(in: .whitespaces)
                        onSave(saved)
                    }
                    .disabled(station.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task(id: station) {
                count = nil
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                count = await AppGraph.shared.stations.count(station)
            }
            .task { genres = await AppGraph.shared.library.genres().map(\.value).sorted() }
        }
        .tint(c.accent)
    }

    /** Energy is 0 to 1 inside, 1 to 10 on screen. */
    private var energy: Binding<Bounds?> {
        Binding(
            get: { station.energy.map { Bounds($0.min.map { ($0 * 10).rounded() }, $0.max.map { ($0 * 10).rounded() }) } },
            set: { station.energy = $0.map { Bounds($0.min.map { $0 / 10 }, $0.max.map { $0 / 10 }) } }
        )
    }
}

/** "Any", or a from and a to. */
private struct BoundsEditor: View {
    @Environment(\.kultr) private var theme
    let label: String
    @Binding var bounds: Bounds?
    let range: ClosedRange<Double>
    let step: Double
    let initial: Bounds
    let text: (Double) -> String

    var body: some View {
        let open = bounds?.isOpen ?? true
        Toggle("Any \(label.lowercased())", isOn: Binding(get: { open }, set: { bounds = $0 ? nil : initial }))
            .tint(theme.colors.accent)
        if !open {
            let low = bounds?.min ?? range.lowerBound
            let high = bounds?.max ?? range.upperBound
            Stepper(value: Binding(get: { low }, set: { bounds = Bounds($0, max($0, high)) }), in: range, step: step) {
                Text("From \(text(low))")
            }
            Stepper(value: Binding(get: { high }, set: { bounds = Bounds(min($0, low), $0) }), in: range, step: step) {
                Text("To \(text(high))")
            }
        }
    }
}

private struct GenrePicker: View {
    @Environment(\.kultr) private var theme
    let all: [String]
    @Binding var chosen: [String]
    @State private var filter = ""

    var body: some View {
        let shown = filter.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(filter) }
        List {
            if all.isEmpty {
                Text("No genres in your library yet.").foregroundStyle(theme.colors.ink3)
            }
            ForEach(shown, id: \.self) { genre in
                let on = chosen.contains(genre)
                Button {
                    if on { chosen.removeAll { $0 == genre } } else { chosen.append(genre) }
                } label: {
                    HStack {
                        Text(genre).foregroundStyle(theme.colors.ink)
                        Spacer()
                        if on { Image(systemName: "checkmark").foregroundStyle(theme.colors.accent) }
                    }
                }
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .searchable(text: $filter, prompt: "Filter genres")
        .navigationTitle("Genres")
        .toolbar {
            if !chosen.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { Button("Clear") { chosen = [] } }
            }
        }
    }
}
