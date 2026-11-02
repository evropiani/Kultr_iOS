import Foundation

/**
 * One month of listening on this phone, for the recap in Listening. Built from
 * the phone's own history, because the server only keeps a play count and the
 * last time per track, not each play.
 */
struct MonthRecap: Equatable {
    /** Something played this month, and how often. */
    struct Entry<Item: Equatable>: Equatable {
        let item: Item
        let plays: Int
        let seconds: Int64
    }

    /** An artist or an album, as far as the tracks played know it. */
    struct Name: Equatable {
        let id: String?
        let name: String
        let artist: String?
        let coverArt: String?
    }

    struct Day: Equatable {
        let date: Date
        let seconds: Int64
    }

    /** The first moment of the month. */
    let month: Date
    let seconds: Int64
    let plays: Int
    let tracks: Int
    let artists: Int
    /** Most played first; ties go to more time listened. */
    let topSongs: [Entry<Song>]
    let topArtists: [Entry<Name>]
    let topAlbums: [Entry<Name>]
    /** The day with the most listening. */
    let busiestDay: Day?
    /** Tracks played for the first time on this phone this month. */
    let firstListens: Int
    /** Time listened the month before, to compare with. */
    let previousSeconds: Int64

    var isEmpty: Bool { plays == 0 }
}

/** The months with any listening in [history], newest first. */
func recapMonths(_ history: [HistoryEntry], calendar: Calendar = .current) -> [Date] {
    var months = Set<Date>()
    for entry in history {
        if let month = calendar.dateInterval(of: .month, for: entry.date)?.start { months.insert(month) }
    }
    return months.sorted(by: >)
}

/**
 * The recap of the month that [month] falls in. [songs] resolves the ids in
 * [history]; a track no longer in the library still counts towards the time
 * and the plays, it just can't be listed.
 */
func monthRecap(
    _ history: [HistoryEntry],
    songs: [String: Song],
    month: Date,
    calendar: Calendar = .current,
    top: Int = 10
) -> MonthRecap {
    let interval = calendar.dateInterval(of: .month, for: month) ?? DateInterval(start: month, duration: 0)
    let previous = calendar.date(byAdding: .month, value: -1, to: interval.start)
        .flatMap { calendar.dateInterval(of: .month, for: $0) }

    var seconds: Int64 = 0
    var previousSeconds: Int64 = 0
    var plays = 0
    var bySong: [String: (plays: Int, seconds: Int64)] = [:]
    var byArtist: [String: (name: MonthRecap.Name, plays: Int, seconds: Int64)] = [:]
    var byAlbum: [String: (name: MonthRecap.Name, plays: Int, seconds: Int64)] = [:]
    var byDay: [Date: Int64] = [:]
    var heardBefore = Set<String>()

    for entry in history {
        let date = entry.date
        if date < interval.start { heardBefore.insert(entry.songId) }
        if let previous, previous.contains(date), date < interval.start { previousSeconds += Int64(entry.seconds) }
        guard date >= interval.start, date < interval.end else { continue }
        let time = Int64(entry.seconds)
        seconds += time
        plays += 1
        bySong[entry.songId, default: (0, 0)].plays += 1
        bySong[entry.songId, default: (0, 0)].seconds += time
        byDay[calendar.startOfDay(for: date), default: 0] += time
        guard let song = songs[entry.songId] else { continue }
        if let artist = song.artist ?? song.artistId {
            let key = song.artistId ?? artist
            let name = MonthRecap.Name(id: song.artistId, name: artist, artist: nil, coverArt: nil)
            byArtist[key, default: (name, 0, 0)].plays += 1
            byArtist[key, default: (name, 0, 0)].seconds += time
        }
        if let album = song.album ?? song.albumId {
            let key = song.albumId ?? album
            let name = MonthRecap.Name(id: song.albumId, name: album, artist: song.artist, coverArt: song.coverArt)
            byAlbum[key, default: (name, 0, 0)].plays += 1
            byAlbum[key, default: (name, 0, 0)].seconds += time
        }
    }

    func ranked<Item: Equatable>(_ items: [(Item, Int, Int64, String)]) -> [MonthRecap.Entry<Item>] {
        items
            .sorted { a, b in a.1 != b.1 ? a.1 > b.1 : a.2 != b.2 ? a.2 > b.2 : a.3 < b.3 }
            .prefix(top)
            .map { MonthRecap.Entry(item: $0.0, plays: $0.1, seconds: $0.2) }
    }

    let artistKeys = Set(byArtist.values.map { $0.name.id ?? $0.name.name })
    return MonthRecap(
        month: interval.start,
        seconds: seconds,
        plays: plays,
        tracks: bySong.count,
        artists: artistKeys.count,
        topSongs: ranked(bySong.compactMap { id, count -> (Song, Int, Int64, String)? in
            songs[id].map { ($0, count.plays, count.seconds, id) }
        }),
        topArtists: ranked(byArtist.map { key, value in (value.name, value.plays, value.seconds, key) }),
        topAlbums: ranked(byAlbum.map { key, value in (value.name, value.plays, value.seconds, key) }),
        busiestDay: byDay.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }
            .map { MonthRecap.Day(date: $0.key, seconds: $0.value) },
        firstListens: bySong.keys.filter { !heardBefore.contains($0) }.count,
        previousSeconds: previousSeconds
    )
}

extension HistoryEntry {
    var date: Date { Date(timeIntervalSince1970: Double(playedAt) / 1000) }
}
