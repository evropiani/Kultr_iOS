import Foundation

/**
 * Suggested songs under a playlist, as on Spotify: a few songs that would
 * fit, each with a + to add it. Add one and the next suggestions are songs
 * like the one just added. They come from Karousel's picker, so the server's
 * similar songs and artists lead when it has them, and the library carries
 * on when it does not. The same rules as Kultr for Android and the web.
 */
@MainActor
enum PlaylistSuggestions {
    /** How many suggestions show at a time. */
    static let count = 5

    /** Songs from the playlist, or favourites, that suggestions start from. */
    private static let seedCount = 3

    /** Whatever generator was passed in, as a concrete one that `shuffled(using:)` accepts. */
    private struct AnyRandom: RandomNumberGenerator {
        var base: any RandomNumberGenerator
        mutating func next() -> UInt64 { base.next() }
    }

    /**
     * What suggestions are drawn from: the song just added first, so what
     * comes next is like it, then songs from the playlist by other artists,
     * picked at random so that refreshing gives something new.
     */
    static func seeds<R: RandomNumberGenerator>(_ playlist: [Song], added: Song?, using random: inout R) -> [Song] {
        var picked: [Song] = []
        var artists = Set<String>()
        func push(_ song: Song) {
            let artist = Karousel.artistKey(song.artist)
            if artist.isEmpty || !artists.insert(artist).inserted { return }
            picked.append(song)
        }
        if let added { push(added) }
        for song in playlist.shuffled(using: &random) {
            if picked.count >= seedCount { break }
            if song.id != added?.id { push(song) }
        }
        return picked
    }

    /** Ids and keys of what not to suggest: the playlist (the same song on another album too), and anything shown already. */
    static func exclude(_ playlist: [Song], leaveOut: [Song] = []) -> Set<String> {
        var out = Set<String>()
        for song in playlist + leaveOut {
            out.insert(song.id)
            out.insert(Karousel.key(song))
        }
        return out
    }

    /**
     * Songs to suggest for [playlist] (the song just added included). An
     * empty playlist starts from what the user plays most and has hearted.
     */
    static func suggest(
        sources: KarouselSources,
        playlist: [Song],
        added: Song? = nil,
        leaveOut: [Song] = [],
        count: Int? = nil,
        random: any RandomNumberGenerator = SystemRandomNumberGenerator()
    ) async -> [Song] {
        let wanted = count ?? Self.count
        var generator = AnyRandom(base: random)
        var from = Self.seeds(playlist, added: added, using: &generator)
        if from.isEmpty {
            let favourites = (try? await sources.favourites(40)) ?? []
            from = Self.seeds(Array(favourites.prefix(40)), added: nil, using: &generator)
        }
        if from.isEmpty || wanted <= 0 { return [] }
        return await Karousel(sources: sources).next(
            Karousel.Input(seeds: from, exclude: Self.exclude(playlist, leaveOut: leaveOut), count: wanted, random: generator)
        )
    }
}
