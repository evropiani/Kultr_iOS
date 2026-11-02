import SwiftUI

/**
 * A month of listening on this phone: how long, how much, the tracks, albums
 * and artists you played most, and the day you listened the longest. Any month
 * with history can be picked from the toolbar.
 */
struct RecapScreen: View {
    @Environment(\.kultr) private var theme
    @State private var history: [HistoryEntry] = []
    @State private var songs: [String: Song] = [:]
    @State private var months: [Date] = []
    @State private var month: Date?
    @State private var loaded = false

    static let monthTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter
    }()

    private static let monthName: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        return formatter
    }()

    private static let dayTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter
    }()

    var body: some View {
        let graph = AppGraph.shared
        let recap = month.map { monthRecap(history, songs: songs, month: $0) }
        Group {
            if !loaded {
                ScrollView { SkeletonRows(count: 8, artwork: true).padding(.top, 72) }
                    .scrollDisabled(true)
            } else if let recap, !recap.isEmpty {
                ScrollView { content(recap) }
            } else {
                EmptyState(
                    icon: "calendar",
                    title: "No months to look back on yet",
                    message: "Kultr makes a recap from what you play on this phone. Play a few tracks and this month's shows up here."
                )
                .frame(maxHeight: .infinity)
            }
        }
        .navigationTitle(month.map { Self.monthTitle.string(from: $0) } ?? "Monthly recap")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if months.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Month", selection: Binding(get: { month ?? months[0] }, set: { pick($0) })) {
                            ForEach(months, id: \.self) { Text(Self.monthTitle.string(from: $0)).tag($0) }
                        }
                    } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("Choose a month")
                }
            }
        }
        .kultrScreen()
        .task(id: graph.library.historyVersion) { await load() }
    }

    private func pick(_ next: Date) {
        withAnimation(theme.ease) { month = next }
    }

    @ViewBuilder
    private func content(_ recap: MonthRecap) -> some View {
        let graph = AppGraph.shared
        let c = theme.colors
        let top = recap.topSongs.map(\.item)
        let thisMonth = Calendar.current.isDate(recap.month, equalTo: Date(), toGranularity: .month)
        LazyVStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Format.duration(recap.seconds))
                    .font(.largeTitle.bold())
                    .foregroundStyle(c.ink)
                    .contentTransition(.numericText())
                Text("\(Format.count(recap.plays, "play")) · \(Format.count(recap.tracks, "track")) · \(Format.count(recap.artists, "artist"))")
                    .font(KFont.bodyMedium)
                    .foregroundStyle(c.ink2)
                Text(comparison(recap, thisMonth: thisMonth))
                    .font(KFont.bodySmall)
                    .foregroundStyle(c.ink3)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)

            if !top.isEmpty {
                WideButton(title: "Play this month's top tracks", icon: "play.fill", prominent: true) {
                    graph.actions.play(top)
                }
                .padding(.horizontal, 16)

                SectionHeader("Top tracks")
                ForEach(Array(recap.topSongs.enumerated()), id: \.element.item.id) { index, entry in
                    CountedSongRow(song: entry.item, count: entry.plays) { graph.actions.play(top, index) }
                }
            }

            let albums = recap.topAlbums.compactMap { entry -> Album? in
                guard let id = entry.item.id else { return nil }
                return Album(id: id, name: entry.item.name, artist: entry.item.artist, coverArt: entry.item.coverArt)
            }
            if !albums.isEmpty {
                SectionHeader("Top albums")
                Shelf(items: albums) { AlbumCard(album: $0) }
            }

            if !recap.topArtists.isEmpty {
                SectionHeader("Top artists")
                PlayBars(rows: recap.topArtists.map { PlayBar(name: $0.item.name, artistId: $0.item.id, plays: Int64($0.plays)) })
            }

            SectionHeader("The month in numbers")
            VStack(alignment: .leading, spacing: 12) {
                if let day = recap.busiestDay {
                    Fact(label: "Your longest day", value: "\(Self.dayTitle.string(from: day.date)) · \(Format.duration(day.seconds))")
                }
                Fact(
                    label: "First listens",
                    value: recap.firstListens == 0
                        ? "Only tracks you had played before"
                        : "\(Format.count(recap.firstListens, "track")) you had never played on this phone"
                )
                if recap.plays > 0 {
                    Fact(label: "On average", value: "\(Format.duration(recap.seconds / Int64(recap.plays))) a play")
                }
            }
            .padding(.horizontal, 16)

            Text("Made from what you played on this phone. Plays on other devices count on your server, but not here.")
                .font(KFont.bodySmall)
                .foregroundStyle(c.ink3)
                .padding(16)
        }
        .padding(.bottom, 24)
    }

    private func comparison(_ recap: MonthRecap, thisMonth: Bool) -> String {
        let previous = Calendar.current.date(byAdding: .month, value: -1, to: recap.month).map { Self.monthName.string(from: $0) } ?? ""
        guard recap.previousSeconds > 0 else { return thisMonth ? "So far this month." : "Nothing played the month before." }
        let before = "\(previous) was \(Format.duration(recap.previousSeconds))."
        return thisMonth ? "So far this month. \(before)" : before
    }

    private func load() async {
        let library = AppGraph.shared.library
        let history = await library.history(20_000)
        let ids = Array(Set(history.map(\.songId)))
        let songs = await library.songsByIds(ids)
        let months = recapMonths(history)
        withAnimation(theme.ease) {
            self.history = history
            self.songs = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            self.months = months
            if month == nil || !months.contains(month!) { month = months.first }
            loaded = true
        }
    }
}

/** A label above a value, for the facts at the end of the recap. */
private struct Fact: View {
    @Environment(\.kultr) private var theme
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(KFont.bodySmall)
                .foregroundStyle(theme.colors.ink3)
            Text(value)
                .font(KFont.bodyLarge)
                .foregroundStyle(theme.colors.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/** A track row with how often it was played at the end. */
struct CountedSongRow: View {
    @Environment(\.kultr) private var theme
    let song: Song
    let count: Int64
    let onTap: () -> Void

    init(song: Song, count: some BinaryInteger, onTap: @escaping () -> Void) {
        self.song = song
        self.count = Int64(count)
        self.onTap = onTap
    }

    var body: some View {
        let graph = AppGraph.shared
        HStack(spacing: 0) {
            SongRow(
                song: song,
                isCurrent: song.id == graph.player.state.current?.id,
                downloaded: graph.offline.downloadedIds.contains(song.id),
                compact: theme.settings.compactRows,
                onTap: onTap
            )
            Text("\(count)×")
                .font(KFont.bodySmall.monospacedDigit())
                .foregroundStyle(theme.colors.ink3)
                .padding(.trailing, 12)
        }
    }
}

struct PlayBar: Hashable {
    let name: String?
    let artistId: String?
    let plays: Int64
}

/** Artists as orange bars, longest for the most plays; each opens its artist. */
struct PlayBars: View {
    @Environment(\.kultr) private var theme
    let rows: [PlayBar]

    var body: some View {
        let c = theme.colors
        let peak = max(1, rows.first?.plays ?? 1)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Button {
                    AppGraph.shared.actions.openArtist(row.artistId)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(row.name ?? "Unknown artist").foregroundStyle(c.ink).lineLimit(1)
                            Spacer()
                            Text(Format.count(Int(row.plays), "play"))
                                .font(KFont.bodySmall.monospacedDigit())
                                .foregroundStyle(c.ink3)
                        }
                        GeometryReader { proxy in
                            Capsule()
                                .fill(c.accent)
                                .frame(width: max(6, proxy.size.width * CGFloat(Double(row.plays) / Double(peak))))
                        }
                        .frame(height: 5)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
                .disabled(row.artistId == nil)
            }
        }
        .padding(.horizontal, 16)
    }
}
