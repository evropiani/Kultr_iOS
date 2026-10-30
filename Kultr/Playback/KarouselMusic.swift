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

    /**
     * How long one search waits for the server, all told; after that it goes
     * on with the library alone. A server asking Last.fm can take its time,
     * and when the queue has already run out, Kultr is quiet while it waits,
     * which iOS does not allow an app in the background for long.
     */
    private static let serverBudget: TimeInterval = 20
    private var deadline = Date.distantFuture

    init(graph: AppGraph) {
        self.graph = graph
    }

    private var library: LibraryRepository { graph.library }

    /**
     * Whether the server can be asked, found out at the start of each search:
     * the phone being online doesn't mean a server at home can be reached.
     * When it can't, Karousel offers only downloaded songs, from the library
     * on the phone, since nothing else would play.
     */
    private var online = false

    private func reachServer() async -> Bool {
        guard !graph.isLocal, let client = graph.auth.client, graph.network.isOnline else { return false }
        deadline = Date().addingTimeInterval(4)
        return await fromServer(false) { (try? await client.ping()) != nil }
    }

    private func playable(_ song: Song) -> Bool {
        !song.isRadio && (graph.isLocal || online || graph.offline.downloadedIds.contains(song.id))
    }

    /** Songs like [seeds] (the track playing first) to follow [queued], leaving out what played in the last few hours. */
    func next(seeds: [Song], queued: [Song], count: Int = 10) async -> [Song] {
        let started = Date()
        online = await reachServer()
        var exclude = Set<String>()
        let recent = await library.songsByIds(await library.songIdsPlayedSince(Format.nowMs() - Self.recentMs))
        for song in queued + recent {
            exclude.insert(song.id)
            exclude.insert(Karousel.key(song))
        }
        deadline = Date().addingTimeInterval(Self.serverBudget)
        let karousel = Karousel(sources: self) { Self.logger.info("Karousel: \($0, privacy: .public)") }
        let found = await karousel.next(Karousel.Input(seeds: seeds, exclude: exclude, count: count))
        let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
        PlaybackLog.note("Karousel found \(found.count) songs like “\(seeds.first?.title ?? "?")” in \(seconds) s\(online || graph.isLocal ? "" : " (server out of reach: downloaded songs only)")")
        return found
    }

    /** [body] from the server, or [empty] once this search has waited long enough for it. */
    private func fromServer<T: Sendable>(_ empty: T, _ body: @escaping @MainActor () async -> T) async -> T {
        let left = deadline.timeIntervalSinceNow
        guard left > 0 else { return empty }
        return await withTaskGroup(of: T?.self) { group in
            group.addTask { await body() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(left * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? empty
        }
    }

    func station(_ seed: Song) async throws -> [Song] {
        guard online else { return [] }
        let similar = await fromServer([Song]()) { await self.library.similarSongs(seed.id, count: 50) }
        return await mixingWell(seed, similar.filter(playable))
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
        return await fromServer([ArtistRef]()) {
            (await self.library.artistInfo(id)?.similarArtist ?? []).map { ArtistRef(name: $0.name, id: $0.id) }
        }
    }

    func topSongs(_ artist: ArtistRef, count: Int) async throws -> [Song] {
        guard online else { return [] }
        let top = await fromServer([Song]()) { await self.library.topSongs(artist.name) }
        return Array(top.filter(playable).prefix(count))
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
