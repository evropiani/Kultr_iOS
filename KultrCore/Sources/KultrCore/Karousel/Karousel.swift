import Foundation

/** An artist as the library knows them: the name, and their id where there is one. */
struct ArtistRef: Hashable {
    let name: String
    var id: String? = nil
}

/**
 * Where Karousel finds music. Any of these may come up empty (no connection, a
 * server without Last.fm, music on the phone), and Karousel carries on with
 * the rest. Every song offered must be one that can play right now.
 */
@MainActor
protocol KarouselSources: AnyObject {
    /** Songs like [seed], by any artist: a station started from it. */
    func station(_ seed: Song) async throws -> [Song]

    /** Artists like [artist] that are in the library. */
    func similarArtists(_ artist: ArtistRef) async throws -> [ArtistRef]

    /** [artist]'s best-known songs in the library. */
    func topSongs(_ artist: ArtistRef, count: Int) async throws -> [Song]

    /** The library's songs by any of [artists]. */
    func byArtists(_ artists: [ArtistRef]) async throws -> [Song]

    /** Some of the library's songs in any of [genres]. */
    func inGenres(_ genres: Set<String>, count: Int) async throws -> [Song]

    /** What the user plays most and has hearted, most played first. */
    func favourites(_ count: Int) async throws -> [Song]
}

/**
 * Karousel: when the queue runs out, more music like what has been playing,
 * so it never stops. Ported from KultrDL, by way of Kultr for Android.
 *
 * It draws on a station started from the song now playing (the server's
 * similar songs), on the best-known songs of artists like the ones playing and
 * of those artists themselves, and on the library's songs by any of them.
 * Short of those (with no connection, say, or for music on the phone) it
 * carries on with the library: the same genres first, then what the user
 * plays most.
 */
@MainActor
final class Karousel {
    struct Input {
        /** What has been playing, the song now playing first. */
        var seeds: [Song]
        /** Song ids and [key]s not to play: what is queued and what played lately. */
        var exclude: Set<String> = []
        var count = 10
        var random: any RandomNumberGenerator = SystemRandomNumberGenerator()
    }

    /** No more than this many songs by one artist in a batch. */
    static let maxPerArtist = 2

    /** Which pool each pick comes from first: 0 the station, 1 similar artists, 2 the same artists, 3 the library's own. */
    private static let mix = [0, 1, 0, 2, 0, 1, 3, 0, 1, 2]

    private struct Around {
        let same: [Song]
        let similar: [Song]
        let similarArtists: [ArtistRef]
    }

    /** A list taken from the front, one song at a time. */
    private final class Pool {
        private let songs: [Song]
        private var at = 0
        init(_ songs: [Song]) { self.songs = songs }
        var isEmpty: Bool { at >= songs.count }
        func removeFirst() -> Song {
            defer { at += 1 }
            return songs[at]
        }
    }

    /** Whatever generator [Input] brought, as a concrete one that `shuffled(using:)` accepts. */
    private struct Random: RandomNumberGenerator {
        var base: any RandomNumberGenerator
        mutating func next() -> UInt64 { base.next() }
    }

    private let sources: KarouselSources
    private let log: (String) -> Void
    private var random = Random(base: SystemRandomNumberGenerator())

    init(sources: KarouselSources, log: @escaping (String) -> Void = { _ in }) {
        self.sources = sources
        self.log = log
    }

    func next(_ input: Input) async -> [Song] {
        let seeds = input.seeds.filter { !$0.isRadio && !($0.artist ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        if seeds.isEmpty || input.count <= 0 { return [] }
        random = Random(base: input.random)
        var seenArtists = Set<String>()
        let artists = Array(
            seeds.map { ArtistRef(name: Self.primary($0.artist), id: $0.artistId) }
                .filter { seenArtists.insert(Self.artistKey($0.name)).inserted }
                .prefix(3)
        )

        async let stationSongs = station(seeds)
        let found = await withTaskGroup(of: (Int, Around).self) { group -> [Around] in
            for (i, artist) in artists.enumerated() {
                group.addTask { @MainActor in (i, await self.around(artist, similarArtists: i == 0 ? 4 : 2)) }
            }
            var out = [Around?](repeating: nil, count: artists.count)
            for await (i, around) in group { out[i] = around }
            return out.compactMap { $0 }
        }
        let fromStation = await stationSongs

        var nearSeen = Set<String>()
        let near = (artists + found.flatMap { $0.similarArtists }).filter { nearSeen.insert(Self.artistKey($0.name)).inserted }
        let nearKeys = Set(near.map { Self.artistKey($0.name) })
        let seedGenres = Set(seeds.compactMap { $0.genre?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })

        async let theirs = safe("songs by \(near.count) artists", []) { try await self.sources.byArtists(near) }
        async let genres = inGenres(seedGenres)
        async let favourites = safe("favourites", []) { try await self.sources.favourites(200) }

        // In order of preference: the station, artists like these, these artists, the library's songs by any of them.
        let pools = [
            fromStation,
            Self.roundRobin(found.map { $0.similar }),
            Self.roundRobin(found.map { $0.same }),
            shuffled(await theirs.filter { nearKeys.contains(Self.artistKey($0.artist)) }),
        ].map(Pool.init)
        let backups = [
            shuffled(await genres.filter { !nearKeys.contains(Self.artistKey($0.artist)) }),
            shuffled(Array(await favourites.prefix(200))),
        ].map(Pool.init)

        var picked: [Song] = []
        var taken = input.exclude
        var perArtist: [String: Int] = [:]
        func take(_ pool: Pool) -> Bool {
            while !pool.isEmpty {
                let song = pool.removeFirst()
                let songKey = Self.key(song)
                let artist = Self.artistKey(song.artist)
                if song.isRadio || taken.contains(song.id) || taken.contains(songKey) || perArtist[artist, default: 0] >= Self.maxPerArtist { continue }
                taken.insert(song.id)
                taken.insert(songKey)
                perArtist[artist, default: 0] += 1
                picked.append(song)
                return true
            }
            return false
        }
        // Mostly the station, with artists like these, these artists and the library's own mixed in.
        var turn = 0
        while picked.count < input.count {
            let first = Self.mix[turn % Self.mix.count]
            turn += 1
            if take(pools[first]) { continue }
            if !pools.contains(where: { take($0) }) { break }
        }
        while picked.count < input.count {
            if !backups.contains(where: { take($0) }) { break }
        }

        let origins = [fromStation, found.flatMap { $0.similar }, found.flatMap { $0.same }].map { Set($0.map { $0.id }) }
        let counts = origins.map { ids in picked.filter { ids.contains($0.id) }.count }
        log(
            "\(picked.count) songs like \(artists.map { $0.name }.joined(separator: ", ")): \(counts[0]) from the station, " +
                "\(counts[1]) by similar artists, \(counts[2]) by the same artists, \(picked.count - counts.reduce(0, +)) more from the library"
        )
        return Self.spread(picked)
    }

    /** Songs like the first seed that has any (the song playing, or the one before it). */
    private func station(_ seeds: [Song]) async -> [Song] {
        for seed in seeds.prefix(2) {
            let found = await safe("songs like \(seed.title)", []) { try await self.sources.station(seed) }
            if !found.isEmpty { return found }
        }
        return []
    }

    private func inGenres(_ genres: Set<String>) async -> [Song] {
        if genres.isEmpty { return [] }
        return await safe("songs in \(genres.sorted().joined(separator: ", "))", []) { try await self.sources.inGenres(genres, count: 200) }
    }

    /** The artist's best-known songs, and songs by artists like them. */
    private func around(_ artist: ArtistRef, similarArtists: Int) async -> Around {
        async let top = safe("top songs of \(artist.name)", []) { try await self.sources.topSongs(artist, count: 6) }
        let related = Array(
            await safe("artists like \(artist.name)", []) { try await self.sources.similarArtists(artist) }
                .filter { Self.artistKey($0.name) != Self.artistKey(artist.name) }
                .prefix(8)
        )
        let chosen = Array(shuffled(related).prefix(similarArtists))
        let theirs = await withTaskGroup(of: (Int, [Song]).self) { group -> [[Song]] in
            for (i, other) in chosen.enumerated() {
                group.addTask { @MainActor in
                    let songs = await self.safe("top songs of \(other.name)", []) { try await self.sources.topSongs(other, count: 5) }
                    return (i, Array(self.shuffled(songs).prefix(3)))
                }
            }
            var out = [[Song]](repeating: [], count: chosen.count)
            for await (i, songs) in group { out[i] = songs }
            return out
        }
        return Around(same: Array(shuffled(await top).prefix(3)), similar: Self.roundRobin(theirs), similarArtists: related)
    }

    private func safe<T>(_ what: String, _ empty: T, _ body: () async throws -> T) async -> T {
        do {
            return try await body()
        } catch {
            if !(error is CancellationError) { log("\(what) failed: \(error.localizedDescription)") }
            return empty
        }
    }

    private func shuffled<T>(_ items: [T]) -> [T] {
        items.shuffled(using: &random)
    }

    // ------------------------------------------------------------- matching --

    private static let featuring = try! NSRegularExpression(
        pattern: #"\s+(?:feat\.?|ft\.?|featuring|with|vs\.?|x)\s+|\s*[,;/&+]\s*"#,
        options: [.caseInsensitive]
    )
    private static let titleNoise = try! NSRegularExpression(
        pattern: #"\s*[(\[][^)\]]*(?:feat|remaster|version|edit|mono|stereo|explicit|clean|bonus|deluxe)[^)\]]*[)\]]"#
            + #"|\s+-\s+[^-]*(?:remaster|version|edit|mono|stereo)[^-]*$"#,
        options: [.caseInsensitive]
    )
    private static let notWords = try! NSRegularExpression(pattern: #"[^\p{L}\p{N}]+"#)

    /** The first-named artist of a credit like "A feat. B" or "A, B & C". */
    static func primary(_ artist: String?) -> String {
        let whole = (artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let ns = whole as NSString
        var start = 0
        for match in featuring.matches(in: whole, range: NSRange(location: 0, length: ns.length)) {
            let piece = ns.substring(with: NSRange(location: start, length: match.range.location - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { return piece }
            start = match.range.location + match.range.length
        }
        let rest = ns.substring(from: start).trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? whole : rest
    }

    /** What artists are compared by: the first-named artist, lower case, without accents or punctuation. */
    static func artistKey(_ artist: String?) -> String { fold(primary(artist)) }

    /** The same song wherever it appears: on another album, remastered, or credited differently. */
    static func key(_ song: Song) -> String {
        let title = song.title as NSString
        let clean = titleNoise.stringByReplacingMatches(in: song.title, range: NSRange(location: 0, length: title.length), withTemplate: "")
        return "song:" + artistKey(song.artist) + "|" + fold(clean)
    }

    private static func fold(_ text: String) -> String {
        let plain = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let spaced = notWords.stringByReplacingMatches(
            in: plain,
            range: NSRange(location: 0, length: (plain as NSString).length),
            withTemplate: " "
        )
        return spaced.trimmingCharacters(in: .whitespaces)
    }

    /** Reorders so the same artist doesn't play twice in a row, where another can go between. */
    static func spread(_ songs: [Song]) -> [Song] {
        var left = songs
        var out: [Song] = []
        out.reserveCapacity(songs.count)
        var last: String?
        while !left.isEmpty {
            let i = left.firstIndex { artistKey($0.artist) != last } ?? 0
            let next = left.remove(at: i)
            out.append(next)
            last = artistKey(next.artist)
        }
        return out
    }

    private static func roundRobin<T>(_ lists: [[T]]) -> [T] {
        var out: [T] = []
        let longest = lists.map(\.count).max() ?? 0
        for i in 0..<longest {
            for list in lists where i < list.count { out.append(list[i]) }
        }
        return out
    }
}
