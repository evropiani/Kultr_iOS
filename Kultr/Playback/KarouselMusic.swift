import Foundation
import os

/**
 * Karousel's music, from the library in use. A server offers its similar songs
 * and similar artists and their best-known songs (when it has Last.fm set up);
 * the library itself carries on from there, and is all there is for the music
 * on the phone. Offline, only downloaded songs are offered, since nothing else
 * would play.
 */
@MainActor
final class KarouselMusic: KarouselSources {
    private let graph: AppGraph
    private static let logger = Logger(subsystem: "app.kultr.ios", category: "Karousel")

    /** Songs played this recently are not offered again. */
    private static let recentMs: Int64 = 3 * 60 * 60 * 1000

    /** Where a song not analysed yet sits among analysed ones: in the middle. */
    private static let unknownAffinity = 0.5

    init(graph: AppGraph) {
        self.graph = graph
    }

    private var library: LibraryRepository { graph.library }

    /** Whether the server can be asked: the library is a server's, and it can be reached. */
    private var online: Bool {
        !graph.isLocal && graph.auth.client != nil && graph.network.isOnline
    }

    private func playable(_ song: Song) -> Bool {
        !song.isRadio && (graph.isLocal || online || graph.offline.downloadedIds.contains(song.id))
    }

    /** Songs like [seeds] (the track playing first) to follow [queued], leaving out what played in the last few hours. */
    func next(seeds: [Song], queued: [Song], count: Int = 10) async -> [Song] {
        var exclude = Set<String>()
        let recent = await library.songsByIds(await library.songIdsPlayedSince(Format.nowMs() - Self.recentMs))
        for song in queued + recent {
            exclude.insert(song.id)
            exclude.insert(Karousel.key(song))
        }
        let karousel = Karousel(sources: self) { Self.logger.info("Karousel: \($0, privacy: .public)") }
        return await karousel.next(Karousel.Input(seeds: seeds, exclude: exclude, count: count))
    }

    func station(_ seed: Song) async throws -> [Song] {
        guard online else { return [] }
        return await mixingWell(seed, await library.similarSongs(seed.id, count: 50).filter(playable))
    }

    /**
     * With InjeKt on, the songs that mix best out of [seed] come first, as far
     * as analyses already made can tell; the rest keep the server's order.
     */
    private func mixingWell(_ seed: Song, _ songs: [Song]) async -> [Song] {
        guard graph.settings.current.injektEnabled, !songs.isEmpty else { return songs }
        let analyses = await graph.analysis.cachedMany(songs.map { $0.id } + [seed.id])
        guard let from = analyses[seed.id] else { return songs }
        let scored = songs.enumerated().map { i, song in
            (i, song, analyses[song.id].map { affinity(from, $0) } ?? Self.unknownAffinity)
        }
        // Best first; equal scores keep the server's order.
        return scored.sorted { $0.2 != $1.2 ? $0.2 > $1.2 : $0.0 < $1.0 }.map { $0.1 }
    }

    func similarArtists(_ artist: ArtistRef) async throws -> [ArtistRef] {
        guard let id = artist.id, online else { return [] }
        return (await library.artistInfo(id)?.similarArtist ?? []).map { ArtistRef(name: $0.name, id: $0.id) }
    }

    func topSongs(_ artist: ArtistRef, count: Int) async throws -> [Song] {
        guard online else { return [] }
        return Array(await library.topSongs(artist.name).filter(playable).prefix(count))
    }

    func byArtists(_ artists: [ArtistRef]) async throws -> [Song] {
        await library.songsByArtists(ids: artists.compactMap { $0.id }, names: artists.map { $0.name }).filter(playable)
    }

    func inGenres(_ genres: Set<String>, count: Int) async throws -> [Song] {
        let each = max(10, count / max(1, genres.count))
        var songs: [Song] = []
        for genre in genres.sorted().prefix(3) {
            songs += await library.randomSongs(each, genre: genre)
        }
        return songs.filter(playable)
    }

    func favourites(_ count: Int) async throws -> [Song] {
        let played = await library.mostPlayedSongs(count)
        let hearted = Array(await library.starredSongs().shuffled().prefix(count / 2))
        var downloaded: [Song] = []
        if !online && !graph.isLocal {
            downloaded = await library.songsByIds(Array(graph.offline.downloadedIds.shuffled().prefix(count)))
        }
        // Anything at all from the library last, for a library with no plays or hearts yet.
        let any = await library.randomSongs(count)
        var seen = Set<String>()
        return (played + hearted + downloaded + any).filter { seen.insert($0.id).inserted && playable($0) }
    }
}
