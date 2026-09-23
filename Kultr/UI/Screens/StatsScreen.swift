import SwiftUI

private struct StatsSummary {
    let plays: Int
    let seconds: Int64
    let topSongs: [(Song, Int)]
    let topArtists: [(String, Int64)]
    let days: [(Date, Int64)]
}

private func summarise(_ history: [HistoryEntry], _ songs: [Song]) -> StatsSummary {
    let byId = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let calendar = Calendar.current
    var plays: [String: Int] = [:]
    var artistSeconds: [String: Int64] = [:]
    var daySeconds: [Date: Int64] = [:]
    var total: Int64 = 0
    for entry in history {
        let seconds = Int64(entry.seconds)
        total += seconds
        plays[entry.songId, default: 0] += 1
        if let artist = byId[entry.songId]?.artist { artistSeconds[artist, default: 0] += seconds }
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: Double(entry.playedAt) / 1000))
        daySeconds[day, default: 0] += seconds
    }
    let today = calendar.startOfDay(for: Date())
    let days: [(Date, Int64)] = (0...13).reversed().compactMap { back in
        guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
        return (day, daySeconds[day] ?? 0)
    }
    let topSongs: [(Song, Int)] = plays.sorted { $0.value > $1.value }
        .compactMap { entry in byId[entry.key].map { ($0, entry.value) } }
        .prefix(20)
        .map { $0 }
    let topArtists: [(String, Int64)] = artistSeconds.sorted { $0.value > $1.value }.prefix(10).map { ($0.key, $0.value) }
    return StatsSummary(plays: history.count, seconds: total, topSongs: topSongs, topArtists: topArtists, days: days)
}

struct StatsScreen: View {
    @Environment(\.kultr) private var theme
    @State private var history: [HistoryEntry]?
    @State private var summary: StatsSummary?
    @State private var confirm = false

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        ZStack(alignment: .top) {
            AccentWash()
            VStack(spacing: 0) {
                BackBar(title: "Listening")
                if let history, history.isEmpty {
                    EmptyState(icon: "chart.bar.fill", title: "No listening history yet", message: "Play something and Kultr starts keeping track. History stays on this phone.")
                } else if history == nil {
                    LoadingView()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(Format.count(summary?.plays ?? history?.count ?? 0, "play")) · \(Format.duration(summary?.seconds ?? 0)) of music")
                                    .font(KFont.titleLarge)
                                    .foregroundStyle(c.ink)
                                Pill("Clear history", icon: "trash") { confirm = true }
                            }
                            .padding(16)
                            if let s = summary {
                                SectionHeader("The last two weeks", icon: "chart.bar.fill")
                                GlassPanel { DayChart(days: s.days) }
                                    .padding(.horizontal, 16)
                                if !s.topArtists.isEmpty {
                                    SectionHeader("Top artists")
                                    let peak = max(1, s.topArtists[0].1)
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(Array(s.topArtists.enumerated()), id: \.offset) { _, entry in
                                            HStack {
                                                Text(entry.0).foregroundStyle(c.ink).lineLimit(1)
                                                Spacer()
                                                Text(Format.duration(entry.1)).foregroundStyle(c.ink3)
                                            }
                                            GeometryReader { proxy in
                                                LinearGradient(colors: [c.accent, c.accent.opacity(0.3)], startPoint: .leading, endPoint: .trailing)
                                                    .frame(width: proxy.size.width * CGFloat(Double(entry.1) / Double(peak)))
                                            }
                                            .frame(height: 4)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                                if !s.topSongs.isEmpty {
                                    SectionHeader("Most played here")
                                    let songs = s.topSongs.map { $0.0 }
                                    ForEach(Array(s.topSongs.enumerated()), id: \.offset) { index, entry in
                                        HStack(spacing: 0) {
                                            SongRow(
                                                song: entry.0,
                                                isCurrent: entry.0.id == graph.player.state.current?.id,
                                                downloaded: graph.offline.downloadedIds.contains(entry.0.id),
                                                compact: theme.settings.compactRows,
                                                onTap: { graph.actions.play(songs, index) }
                                            )
                                            Text("\(entry.1)×")
                                                .font(KFont.bodySmall)
                                                .foregroundStyle(c.ink3)
                                                .padding(.trailing, 12)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .kultrScreen()
        .task(id: graph.library.historyVersion) {
            let entries = await graph.library.history(5000)
            var seen = Set<String>()
            let ids = entries.map { $0.songId }.filter { seen.insert($0).inserted }
            let songs = await graph.library.songsByIds(ids)
            summary = summarise(entries, songs)
            history = entries
        }
        .alert("Clear listening history?", isPresented: $confirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { Task { await graph.library.clearHistory() } }
        } message: {
            Text("Your stats on this phone start again from nothing. Play counts on the server are not touched.")
        }
    }
}

private struct DayChart: View {
    @Environment(\.kultr) private var theme
    let days: [(Date, Int64)]

    var body: some View {
        let c = theme.colors
        let peak = max(1, days.map { $0.1 }.max() ?? 0)
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.setLocalizedDateFormatFromTemplate("EEEEE")
            return f
        }()
        VStack(spacing: 6) {
            Canvas { context, size in
                let gap: CGFloat = 6
                let count = CGFloat(max(1, days.count))
                let barWidth = (size.width - gap * (count - 1)) / count
                for (i, day) in days.enumerated() {
                    let h = max(2, CGFloat(Double(day.1) / Double(peak)) * size.height)
                    let rect = CGRect(x: CGFloat(i) * (barWidth + gap), y: size.height - h, width: barWidth, height: h)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 4),
                        with: .linearGradient(
                            Gradient(colors: [c.accent, c.accent.opacity(0.35)]),
                            startPoint: CGPoint(x: 0, y: rect.minY),
                            endPoint: CGPoint(x: 0, y: rect.maxY)
                        )
                    )
                }
            }
            .frame(height: 120)
            HStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                    Text(i % 2 == 0 ? formatter.string(from: day.0) : "")
                        .font(KFont.labelSmall)
                        .foregroundStyle(c.ink3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
