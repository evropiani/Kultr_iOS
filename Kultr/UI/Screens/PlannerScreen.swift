import SwiftUI

/**
 * The energy planner: draw how the next stretch should feel, low to high,
 * and Kultr builds a set from InjeKt's analysis that follows the line, with
 * tempos and keys that mix into each other. Play it, or keep it as a playlist.
 */
struct PlannerScreen: View {
    @Environment(\.kultr) private var theme
    @State private var curve = EnergyCurve.warmUpAndPeak.resampled(PlannerScreen.points)
    @State private var minutes = 60
    @State private var source: Station?
    @State private var plan: [PlannedTrack] = []
    @State private var building = false
    @State private var analysed = 0
    @State private var saving = false
    @State private var name = ""

    static let points = 25
    let initialMinutes: Int?

    init(minutes: Int? = nil) {
        initialMinutes = minutes
    }

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Draw the shape of the set with your finger: low is calm, high is peak.")
                    .font(KFont.bodyMedium)
                    .foregroundStyle(c.ink2)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                EnergyCanvas(curve: $curve, minutes: minutes, plan: plan)
                    .frame(height: 220)
                    .padding(16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        preset("Warm up and peak", .warmUpAndPeak)
                        preset("Steady", .steady)
                        preset("Build", .build)
                        preset("Wind down", .windDown)
                    }
                    .padding(.horizontal, 16)
                }

                Picker("Length", selection: $minutes) {
                    Text("30 min").tag(30)
                    Text("1 hour").tag(60)
                    Text("90 min").tag(90)
                    Text("2 hours").tag(120)
                }
                .pickerStyle(.segmented)
                .padding(16)

                HStack {
                    Text("From")
                        .font(KFont.bodyLarge)
                        .foregroundStyle(c.ink)
                    Spacer()
                    Menu {
                        Button("Your whole library") { source = nil }
                        ForEach(graph.stations.all) { station in
                            Button(station.title) { source = station }
                        }
                    } label: {
                        PillLabel(text: source?.title ?? "Your whole library", icon: "chevron.up.chevron.down")
                    }
                }
                .padding(.horizontal, 16)

                WideButton(title: building ? "Building…" : (plan.isEmpty ? "Build the set" : "Build it again"), icon: "waveform.path.ecg", prominent: plan.isEmpty, enabled: !building) {
                    Task { await build() }
                }
                .padding(16)

                if analysed < 30 {
                    AnalysisNote().padding(.horizontal, 16)
                }

                if !plan.isEmpty {
                    let songs = plan.map(\.song)
                    let length = (plan.last.map { $0.startsAt + Double($0.song.duration ?? 0) } ?? 0)
                    HStack(spacing: 12) {
                        WideButton(title: "Play the set", icon: "play.fill", prominent: true) {
                            graph.actions.play(songs)
                            graph.messages.show(String(localized: "Playing your set: \(Format.count(songs.count, "track"))"))
                        }
                        WideButton(title: "Save", icon: "text.badge.plus", prominent: false) {
                            name = String(localized: "Set, \(Format.duration(Int64(length)))")
                            saving = true
                        }
                    }
                    .padding(.horizontal, 16)
                    SectionHeader("\(Format.count(plan.count, "track")) · \(Format.duration(Int64(length)))")
                    ForEach(Array(plan.enumerated()), id: \.element.song.id) { index, track in
                        HStack(spacing: 8) {
                            Text(Format.time(track.startsAt))
                                .font(KFont.bodySmall.monospacedDigit())
                                .foregroundStyle(c.ink3)
                                .frame(width: 44, alignment: .trailing)
                            SongRow(song: track.song, isCurrent: track.song.id == graph.player.state.current?.id, compact: true) {
                                graph.actions.play(songs, index)
                            }
                            EnergyBadge(energy: track.energy)
                                .padding(.trailing, 12)
                        }
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .navigationTitle("Energy planner")
        .navigationBarTitleDisplayMode(.large)
        .kultrScreen()
        .task(id: graph.library.analysisVersion) { analysed = await graph.analysis.analysedCount() }
        .onAppear { if let initialMinutes { minutes = [30, 60, 90, 120].min { abs($0 - initialMinutes) < abs($1 - initialMinutes) } ?? 60 } }
        .alert("Save the set", isPresented: $saving) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let title = name.trimmingCharacters(in: .whitespaces)
                let songs = plan.map(\.song)
                Task {
                    if let error = await graph.library.createPlaylist(title, songs) { graph.messages.error(error) } else { graph.messages.show(String(localized: "Saved “\(title)”"), .success) }
                }
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func preset(_ label: String, _ shape: EnergyCurve) -> some View {
        Pill(label) {
            withAnimation(theme.ease) { curve = shape.resampled(Self.points) }
            plan = []
        }
    }

    private func build() async {
        let graph = AppGraph.shared
        building = true
        defer { building = false }
        let pool: [(Song, TrackAnalysis)]
        if let source {
            pool = await graph.stations.pool(source).compactMap { song, analysis in analysis.map { (song, $0) } }
        } else {
            pool = await graph.stations.pool(Station(name: "All", bpm: Bounds(1, 400))).compactMap { song, analysis in analysis.map { (song, $0) } }
        }
        guard pool.count >= 5 else {
            graph.messages.show("Not enough analysed tracks for a set yet. InjeKt has to analyse a few more first.")
            return
        }
        let curve = self.curve
        let minutes = self.minutes
        let result = await Task.detached(priority: .userInitiated) {
            var random = SystemRandomNumberGenerator()
            return planSet(curve: curve, minutes: minutes, candidates: pool, overlap: 8, random: &random)
        }.value
        withAnimation(theme.ease) { plan = result }
        if result.isEmpty { graph.messages.show("Nothing fits that shape yet.") }
    }
}

/** The drawing: a grid, the line you drew, filled beneath, and the planned tracks as dots. */
private struct EnergyCanvas: View {
    @Environment(\.kultr) private var theme
    @Binding var curve: EnergyCurve
    let minutes: Int
    let plan: [PlannedTrack]
    @State private var lastIndex: Int?

    var body: some View {
        let c = theme.colors
        GeometryReader { proxy in
            let size = proxy.size
            Canvas { context, size in
                let count = curve.points.count
                func point(_ i: Int) -> CGPoint {
                    CGPoint(x: size.width * CGFloat(i) / CGFloat(count - 1), y: size.height * CGFloat(1 - curve.points[i]))
                }
                // The grid: a line every 20% of energy, one every quarter of the set.
                for step in 1..<5 {
                    let y = size.height * CGFloat(step) / 5
                    context.fill(Path(CGRect(x: 0, y: y - 0.25, width: size.width, height: 0.5)), with: .color(c.ink4.opacity(0.6)))
                }
                for step in 1..<4 {
                    let x = size.width * CGFloat(step) / 4
                    context.fill(Path(CGRect(x: x - 0.25, y: 0, width: 0.5, height: size.height)), with: .color(c.ink4.opacity(0.6)))
                }
                var line = Path()
                line.move(to: point(0))
                for i in 1..<count { line.addLine(to: point(i)) }
                var area = line
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .color(c.accent.opacity(0.14)))
                context.stroke(line, with: .color(c.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                // What the set actually does.
                let total = Double(minutes * 60)
                for track in plan where track.startsAt <= total {
                    let x = size.width * CGFloat(track.startsAt / total)
                    let y = size.height * CGFloat(1 - track.energy)
                    context.fill(Path(ellipseIn: CGRect(x: x - 4.5, y: y - 4.5, width: 9, height: 9)), with: .color(c.ink))
                }
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(c.sand.opacity(0.5)))
            .overlay(alignment: .topLeading) {
                Text("Peak").font(KFont.labelSmall).foregroundStyle(c.ink3).padding(8)
            }
            .overlay(alignment: .bottomLeading) {
                Text("Calm").font(KFont.labelSmall).foregroundStyle(c.ink3).padding(8)
            }
            .overlay(alignment: .bottomTrailing) {
                Text(minutes >= 60 ? "\(minutes / 60) h\(minutes % 60 == 0 ? "" : " \(minutes % 60) min")" : "\(minutes) min")
                    .font(KFont.labelSmall)
                    .foregroundStyle(c.ink3)
                    .padding(8)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in draw(at: value.location, in: size) }
                    .onEnded { _ in lastIndex = nil }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Energy over the set")
        .accessibilityValue(describe())
        .accessibilityAdjustableAction { direction in
            // VoiceOver: raise or lower the whole line.
            let delta = direction == .increment ? 0.1 : -0.1
            curve = EnergyCurve(curve.points.map { $0 + delta })
        }
    }

    private func draw(at location: CGPoint, in size: CGSize) {
        let count = curve.points.count
        let index = min(count - 1, max(0, Int((location.x / max(1, size.width) * CGFloat(count - 1)).rounded())))
        let value = Double(1 - min(1, max(0, location.y / max(1, size.height))))
        var points = curve.points
        // Fill the gap from the last point drawn, so a fast stroke leaves no holes.
        if let lastIndex, lastIndex != index {
            let from = points[lastIndex]
            let step = index > lastIndex ? 1 : -1
            var i = lastIndex + step
            while i != index {
                let t = Double(i - lastIndex) / Double(index - lastIndex)
                points[i] = from + (value - from) * t
                i += step
            }
        }
        points[index] = value
        curve = EnergyCurve(points)
        lastIndex = index
    }

    private func describe() -> String {
        let start = Int((curve.points.first ?? 0) * 10)
        let peak = Int((curve.points.max() ?? 0) * 10)
        let end = Int((curve.points.last ?? 0) * 10)
        return String(localized: "Starts at \(start), peaks at \(peak), ends at \(end), out of 10")
    }
}

/** A track's energy, 1 to 10, as a small orange number. */
private struct EnergyBadge: View {
    @Environment(\.kultr) private var theme
    let energy: Double

    var body: some View {
        Text("\(max(1, Int((energy * 10).rounded())))")
            .font(KFont.labelLarge.monospacedDigit())
            .foregroundStyle(theme.colors.accent)
            .frame(width: 28, height: 28)
            .background(Circle().fill(theme.colors.accentSoft))
            .accessibilityLabel("Energy \(max(1, Int((energy * 10).rounded()))) of 10")
    }
}
