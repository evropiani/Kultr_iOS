import Foundation

/** A range with either end left open. */
struct Bounds: Codable, Hashable {
    var min: Double?
    var max: Double?

    init(_ min: Double? = nil, _ max: Double? = nil) {
        self.min = min
        self.max = max
    }

    func contains(_ value: Double) -> Bool {
        if let min, value < min { return false }
        if let max, value > max { return false }
        return true
    }

    var isOpen: Bool { min == nil && max == nil }
}

/**
 * A station: rules over the library, played as an endless mix. Kultr picks
 * what fits the rules and InjeKt mixes from one track to the next. Rules
 * about tempo, energy and key need InjeKt's analysis, so they only match
 * tracks it has analysed (or whose tags carry a tempo).
 */
struct Station: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    /** An SF Symbol. */
    var icon: String
    /** Beats per minute. */
    var bpm: Bounds?
    /** 0 to 1, as InjeKt measures it; shown as 1 to 10. */
    var energy: Bounds?
    /** Camelot keys, like "8A"; nil or empty for any. */
    var keys: [String]?
    /** Any of these genres; nil or empty for any. */
    var genres: [String]?
    var years: Bounds?
    var unplayed = false
    var favourites = false
    /** At least this many stars. */
    var minRating: Int?
    /** Albums or artists you gave any of these tags. */
    var tags: [String]?
    /** Added to the library in the last this many days. */
    var addedDays: Int?

    init(
        id: String = UUID().uuidString,
        name: String,
        icon: String = "dot.radiowaves.left.and.right",
        bpm: Bounds? = nil,
        energy: Bounds? = nil,
        keys: [String]? = nil,
        genres: [String]? = nil,
        years: Bounds? = nil,
        unplayed: Bool = false,
        favourites: Bool = false,
        minRating: Int? = nil,
        tags: [String]? = nil,
        addedDays: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.bpm = bpm
        self.energy = energy
        self.keys = keys
        self.genres = genres
        self.years = years
        self.unplayed = unplayed
        self.favourites = favourites
        self.minRating = minRating
        self.tags = tags
        self.addedDays = addedDays
    }

    /** Missing fields fall back to "any", so stations saved by other versions still load. */
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: .name)) ?? "Station"
        icon = (try? c.decode(String.self, forKey: .icon)) ?? "dot.radiowaves.left.and.right"
        bpm = try? c.decodeIfPresent(Bounds.self, forKey: .bpm)
        energy = try? c.decodeIfPresent(Bounds.self, forKey: .energy)
        keys = try? c.decodeIfPresent([String].self, forKey: .keys)
        genres = try? c.decodeIfPresent([String].self, forKey: .genres)
        years = try? c.decodeIfPresent(Bounds.self, forKey: .years)
        unplayed = (try? c.decodeIfPresent(Bool.self, forKey: .unplayed)) ?? false
        favourites = (try? c.decodeIfPresent(Bool.self, forKey: .favourites)) ?? false
        minRating = try? c.decodeIfPresent(Int.self, forKey: .minRating)
        tags = try? c.decodeIfPresent([String].self, forKey: .tags)
        addedDays = try? c.decodeIfPresent(Int.self, forKey: .addedDays)
    }

    /** Rules that only InjeKt's analysis can answer. */
    var needsAnalysis: Bool {
        !(energy?.isOpen ?? true) || !(keys ?? []).isEmpty
    }

    /**
     * Whether [song] fits, given what InjeKt knows about it. [tagged] holds
     * the album and artist ids with any of the station's tags; [addedSince]
     * is the day ("2026-01-31") a track must have been added on or after.
     */
    func matches(_ song: Song, _ analysis: TrackAnalysis?, tagged: Set<String> = [], addedSince: String? = nil) -> Bool {
        if song.isRadio { return false }
        if let tags, !tags.isEmpty {
            guard song.albumId.map({ tagged.contains($0) }) == true || song.artistId.map({ tagged.contains($0) }) == true else { return false }
        }
        if let addedSince, addedDays != nil {
            // ISO dates sort as text; the day is enough.
            guard let created = song.created, String(created.prefix(10)) >= addedSince else { return false }
        }
        if let bpm, !bpm.isOpen {
            let tempo = (analysis?.bpm).flatMap { $0 > 0 ? $0 : nil } ?? song.bpm.flatMap { $0 > 0 ? Double($0) : nil }
            guard let tempo, bpm.contains(tempo) else { return false }
        }
        if let energy, !energy.isOpen {
            guard let value = analysis?.energy, energy.contains(value) else { return false }
        }
        if let keys, !keys.isEmpty {
            guard let key = analysis?.camelot, keys.contains(key) else { return false }
        }
        if let genres, !genres.isEmpty {
            guard let genre = song.genre?.lowercased() else { return false }
            let wanted = genres.map { $0.lowercased() }
            guard wanted.contains(where: { genre == $0 || genre.contains($0) }) else { return false }
        }
        if let years, !years.isOpen {
            guard let year = song.year, years.contains(Double(year)) else { return false }
        }
        if unplayed && (song.playCount ?? 0) > 0 { return false }
        if favourites && !song.isStarred { return false }
        if let minRating, minRating > 0, (song.userRating ?? 0) < minRating { return false }
        return true
    }

    /** One line saying what the rules are, like "96–110 BPM · energy 4–6 · 6A–9A". */
    var summary: String {
        var parts: [String] = []
        if let bpm, !bpm.isOpen { parts.append(Self.range(bpm, unit: " BPM") { String(Int($0.rounded())) }) }
        if let energy, !energy.isOpen { parts.append("energy " + Self.range(energy) { String(Int(($0 * 10).rounded())) }) }
        if let keys, !keys.isEmpty { parts.append(keys.count <= 3 ? keys.joined(separator: ", ") : "\(keys.count) keys") }
        if let genres, !genres.isEmpty { parts.append(genres.count <= 2 ? genres.joined(separator: ", ") : "\(genres.count) genres") }
        if let years, !years.isOpen { parts.append(Self.range(years) { String(Int($0)) }) }
        if unplayed { parts.append("never played") }
        if favourites { parts.append("favourites") }
        if let minRating, minRating > 0 { parts.append("\(minRating)★ and up") }
        if let tags, !tags.isEmpty { parts.append("tagged " + tags.joined(separator: ", ")) }
        if let addedDays { parts.append(addedDays == 365 ? "added this year" : "added in the last \(addedDays) days") }
        return parts.isEmpty ? "Your whole library" : parts.joined(separator: " · ")
    }

    private static func range(_ bounds: Bounds, unit: String = "", _ text: (Double) -> String) -> String {
        switch (bounds.min, bounds.max) {
        case let (low?, high?): return "\(text(low))–\(text(high))\(unit)"
        case let (low?, nil): return "\(text(low))\(unit) and up"
        case let (nil, high?): return "up to \(text(high))\(unit)"
        default: return "any"
        }
    }

    /** A station per decade, made from the years in the library. */
    static func decade(_ start: Int) -> Station {
        Station(id: "decade-\(start)", name: "\(start)s", icon: "calendar", years: Bounds(Double(start), Double(start + 9)))
    }
}

/** The first day a track must have been added on to fit [addedDays], as "2026-01-31". */
func addedSinceDay(_ addedDays: Int?, now: Date = Date()) -> String? {
    guard let addedDays else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: now.addingTimeInterval(-Double(addedDays) * 86_400))
}

/** The stations Kultr starts with; each can be changed or removed. */
let STATION_PRESETS: [Station] = [
    Station(id: "warm-up", name: "Warm Up", icon: "sunrise.fill", bpm: Bounds(112, 124), energy: Bounds(0.5, 0.85)),
    Station(id: "night-drive", name: "Night Drive", icon: "car.fill", bpm: Bounds(88, 112), energy: Bounds(0.35, 0.7)),
    Station(id: "peak-hour", name: "Peak Hour", icon: "flame.fill", bpm: Bounds(120, 135), energy: Bounds(0.8, nil)),
    Station(id: "deep-focus", name: "Deep Focus", icon: "brain.head.profile", bpm: Bounds(60, 100), energy: Bounds(nil, 0.5)),
    Station(id: "wind-down", name: "Wind Down", icon: "moon.stars.fill", bpm: Bounds(50, 95), energy: Bounds(nil, 0.35)),
    Station(id: "unplayed", name: "Unplayed gems", icon: "sparkle", unplayed: true),
    Station(id: "favourites", name: "Favourites", icon: "heart.fill", favourites: true),
]

/** Decades with at least [minimum] tracks in [years], oldest first. */
func decadeStations(_ years: [Int], minimum: Int = 20) -> [Station] {
    var counts: [Int: Int] = [:]
    for year in years where year >= 1900 && year <= 2100 { counts[year / 10 * 10, default: 0] += 1 }
    return counts.filter { $0.value >= minimum }.keys.sorted().map(Station.decade)
}

/**
 * The next songs for a station: what fits [pool], leaving out [exclude],
 * ranked by how well each mixes out of [seed]. When everything has been
 * played, it starts over rather than stopping.
 */
func stationPicks<R: RandomNumberGenerator>(
    pool: [(Song, TrackAnalysis?)],
    seed: TrackAnalysis?,
    exclude: Set<String>,
    queued: Set<String>,
    count: Int,
    random: inout R
) -> [Song] {
    var fresh = pool.filter { !exclude.contains($0.0.id) && !queued.contains($0.0.id) }
    if fresh.isEmpty { fresh = pool.filter { !queued.contains($0.0.id) } }
    return rankAutoQueue(seed: seed, candidates: fresh, count: count, random: &random)
}
