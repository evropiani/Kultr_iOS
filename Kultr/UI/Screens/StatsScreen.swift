import SwiftUI

/** Seconds listened on each of the last fourteen days, oldest first. */
private func lastTwoWeeks(_ history: [HistoryEntry]) -> [(Date, Int64)] {
    let calendar = Calendar.current
    var daySeconds: [Date: Int64] = [:]
    for entry in history {
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: Double(entry.playedAt) / 1000))
        daySeconds[day, default: 0] += Int64(entry.seconds)
    }
    let today = calendar.startOfDay(for: Date())
    return (0...13).reversed().compactMap { back in
        guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
        return (day, daySeconds[day] ?? 0)
    }
}

/**
 * Listening: built on your server's numbers, so it is the same on every
 * device — played recently, played the most, top artists — plus a two-week
 * chart from this phone's own history.
 */
struct StatsScreen: View {
    @Environment(\.kultr) private var theme
    @State private var history: [HistoryEntry] = []
    @State private var recent: [Song] = []
    @State private var mostPlayed: [Song] = []
    @State private var artists: [ArtistPlays] = []
    @State private var total: Int64 = 0
    @State private var pending = 0
    @State private var loaded = false
    @State private var confirm = false

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        let sync = graph.sync
        Group {
            if loaded && total == 0 && history.isEmpty && recent.isEmpty {
                EmptyState(
                    icon: "chart.bar.fill",
                    title: "Nothing played yet",
                    message: "Play something and it shows up here — along with what you play on your server from other devices."
                )
                .frame(maxHeight: .infinity)
            } else if !loaded {
                LoadingView().frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(Format.count(Int(total), "play")) on your server")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(c.ink)
                                .contentTransition(.numericText())
                            Text(
                                pending > 0
                                    ? "\(Format.count(pending, "play")) from this phone waiting to be sent."
                                    : "Counted on your server, so every device sees the same."
                            )
                            .font(KFont.bodySmall)
                            .foregroundStyle(pending > 0 ? c.warning : c.ink3)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                        if !recent.isEmpty {
                            SectionHeader("Played recently", icon: "clock.arrow.circlepath")
                            ForEach(Array(recent.enumerated()), id: \.element.id) { index, song in
                                SongRow(
                                    song: song,
                                    isCurrent: song.id == graph.player.state.current?.id,
                                    downloaded: graph.offline.downloadedIds.contains(song.id),
                                    compact: theme.settings.compactRows,
                                    onTap: { graph.actions.play(recent, index) }
                                )
                            }
                        }
                        if !mostPlayed.isEmpty {
                            SectionHeader("Played the most", icon: "play.fill")
                            ForEach(Array(mostPlayed.enumerated()), id: \.element.id) { index, song in
                                HStack(spacing: 0) {
                                    SongRow(
                                        song: song,
                                        isCurrent: song.id == graph.player.state.current?.id,
                                        downloaded: graph.offline.downloadedIds.contains(song.id),
                                        compact: theme.settings.compactRows,
                                        onTap: { graph.actions.play(mostPlayed, index) }
                                    )
                                    Text("\(song.playCount ?? 0)×")
                                        .font(KFont.bodySmall.monospacedDigit())
                                        .foregroundStyle(c.ink3)
                                        .padding(.trailing, 12)
                                }
                            }
                        }
                        if !artists.isEmpty {
                            SectionHeader("Top artists", icon: "person.2.fill")
                            let peak = max(1, artists[0].plays)
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(artists.enumerated()), id: \.offset) { _, artist in
                                    Button {
                                        graph.actions.openArtist(artist.artistId)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 5) {
                                            HStack {
                                                Text(artist.name ?? "Unknown artist").foregroundStyle(c.ink).lineLimit(1)
                                                Spacer()
                                                Text(Format.count(Int(artist.plays), "play"))
                                                    .font(KFont.bodySmall.monospacedDigit())
                                                    .foregroundStyle(c.ink3)
                                            }
                                            GeometryReader { proxy in
                                                Capsule()
                                                    .fill(LinearGradient(colors: [c.accent, c.accent.opacity(0.35)], startPoint: .leading, endPoint: .trailing))
                                                    .frame(width: max(6, proxy.size.width * CGFloat(Double(artist.plays) / Double(peak))))
                                            }
                                            .frame(height: 5)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(PressScaleStyle())
                                    .disabled(artist.artistId == nil)
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        SectionHeader("The last two weeks on this phone", icon: "chart.bar.fill")
                        GlassPanel {
                            VStack(alignment: .leading, spacing: 12) {
                                DayChart(days: lastTwoWeeks(history))
                                Text("Your server counts plays per track, not each play, so this chart comes from this phone's own history.")
                                    .font(KFont.bodySmall)
                                    .foregroundStyle(c.ink3)
                            }
                        }
                        .padding(.horizontal, 16)
                        Button(role: .destructive) { confirm = true } label: {
                            Label("Clear this phone's history", systemImage: "trash")
                                .font(KFont.labelLarge)
                        }
                        .padding(16)
                    }
                    .padding(.bottom, 24)
                }
                .refreshable { await sync.refreshListeningNow() }
            }
        }
        .background(alignment: .top) { AccentWash() }
        .navigationTitle("Listening")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    sync.refreshListening(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .symbolEffect(.pulse, options: .repeating, isActive: sync.listening)
                }
                .disabled(sync.listening)
                .accessibilityLabel(sync.listening ? "Refreshing" : "Refresh")
            }
        }
        .kultrScreen()
        .task(id: "\(graph.library.historyVersion):\(graph.library.version):\(sync.listeningVersion)") { await load() }
        .alert("Clear this phone's history?", isPresented: $confirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { Task { await graph.library.clearHistory() } }
        } message: {
            Text("The chart starts again from nothing. Play counts on your server are not touched, and plays not sent yet are kept until they are.")
        }
    }

    private func load() async {
        let library = AppGraph.shared.library
        async let history = library.history(5000)
        async let recent = library.recentlyPlayed(12)
        async let most = library.mostPlayedSongs(20)
        async let artists = library.artistPlays(10)
        async let total = library.totalPlays()
        async let pending = library.pendingPlays()
        let values = await (history, recent, most, artists, total, pending)
        withAnimation(theme.ease) {
            self.history = values.0
            self.recent = values.1
            self.mostPlayed = values.2
            self.artists = values.3
            self.total = values.4
            self.pending = values.5
            loaded = true
        }
    }
}

private struct DayChart: View {
    @Environment(\.kultr) private var theme
    let days: [(Date, Int64)]

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return formatter
    }()

    var body: some View {
        let c = theme.colors
        let peak = max(1, days.map { $0.1 }.max() ?? 0)
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    let fraction = CGFloat(Double(day.1) / Double(peak))
                    UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 4, style: .continuous)
                        .fill(LinearGradient(colors: [c.accent, c.accent.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                        .frame(height: max(3, 120 * fraction))
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("\(Self.weekday.string(from: day.0)): \(Format.duration(day.1))")
                }
            }
            .frame(height: 120, alignment: .bottom)
            HStack(spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                    Text(i % 2 == 0 ? Self.weekday.string(from: day.0) : "")
                        .font(KFont.labelSmall)
                        .foregroundStyle(c.ink3)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
