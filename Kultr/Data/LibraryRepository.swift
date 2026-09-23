import Foundation
import Observation

struct PlaylistDetail: Hashable {
    let playlist: Playlist
    let songs: [Song]
    let entryIds: [String]
}

struct SearchResults: Hashable {
    var artists: [Artist] = []
    var albums: [Album] = []
    var songs: [Song] = []

    var isEmpty: Bool { artists.isEmpty && albums.isEmpty && songs.isEmpty }
}

struct NotConnectedError: LocalizedError {
    var errorDescription: String? { "You are not connected to a server." }
}

/**
 * Everything the screens read from the local mirror, and every change the
 * person makes to their library (favourites, ratings, playlists), which goes
 * to the server first and is then reflected locally.
 *
 * Screens reload when one of the version counters moves.
 */
@MainActor
@Observable
final class LibraryRepository {
    /** Bumped when songs, albums, artists, playlists, genres or the sync state change. */
    private(set) var version = 0
    private(set) var historyVersion = 0
    private(set) var downloadsVersion = 0
    private(set) var analysisVersion = 0

    @ObservationIgnored private unowned let graph: AppGraph
    @ObservationIgnored private(set) var db: LibraryDatabase?
    @ObservationIgnored private var databases: [String: LibraryDatabase] = [:]
    @ObservationIgnored private let coalescer = ChangeCoalescer()

    init(graph: AppGraph) {
        self.graph = graph
        coalescer.onFlush = { [weak self] changes in self?.apply(changes) }
    }

    static var directory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kultr", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /** Open (or reuse) the database for a profile. */
    func databaseFor(_ profileId: String) -> LibraryDatabase? {
        if let open = databases[profileId] { return open }
        let url = Self.directory.appendingPathComponent(LibraryDatabase.fileName(profileId: profileId))
        guard let database = try? LibraryDatabase(path: url.path) else { return nil }
        var excluded = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)
        let coalescer = self.coalescer
        database.onChange = { changes in coalescer.note(changes) }
        databases[profileId] = database
        return database
    }

    /** Switch to the active profile's library. */
    func activate(_ profileId: String?) {
        db = profileId.flatMap { databaseFor($0) }
        version += 1
        historyVersion += 1
        downloadsVersion += 1
        analysisVersion += 1
    }

    /** Close and delete everything stored for a server that has been forgotten. */
    func deleteDataFor(_ profileId: String) {
        databases.removeValue(forKey: profileId)?.close()
        let base = Self.directory.appendingPathComponent(LibraryDatabase.fileName(profileId: profileId))
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: base.path + suffix)
        }
    }

    private func apply(_ changes: Set<LibraryChange>) {
        if changes.contains(.library) { version += 1 }
        if changes.contains(.history) { historyVersion += 1 }
        if changes.contains(.downloads) { downloadsVersion += 1 }
        if changes.contains(.analysis) { analysisVersion += 1 }
    }

    private func client() throws -> SubsonicClient {
        guard let client = graph.auth.client else { throw NotConnectedError() }
        return client
    }

    /** Run [body] against the database off the main thread. */
    func read<T: Sendable>(_ empty: T, _ body: @escaping @Sendable (LibraryDatabase) -> T) async -> T {
        guard let db else { return empty }
        return await Task.detached(priority: .userInitiated) { body(db) }.value
    }

    // ---------------------------------------------------------------- reads --

    func counts() async -> LibraryCounts { await read(LibraryCounts()) { $0.counts() } }
    func syncState() async -> SyncState { await read(SyncState()) { $0.syncState() } }
    func albums() async -> [Album] { await read([]) { $0.albums() } }
    func artists() async -> [Artist] { await read([]) { $0.artists() } }
    func songs() async -> [Song] { await read([]) { $0.songs() } }
    func playlists() async -> [Playlist] { await read([]) { $0.playlists().map { $0.playlist } } }
    func genres() async -> [Genre] { await read([]) { $0.genres() } }
    func song(_ id: String) async -> Song? { await read(nil) { $0.song(id) } }
    func album(_ id: String) async -> Album? { await read(nil) { $0.album(id) } }
    func artist(_ id: String) async -> Artist? { await read(nil) { $0.artist(id) } }
    func songsOfAlbum(_ id: String) async -> [Song] { await read([]) { $0.songsOfAlbum(id) } }
    func albumsOfArtist(_ id: String) async -> [Album] { await read([]) { $0.albumsOfArtist(id) } }
    func songsOfArtist(_ id: String) async -> [Song] { await read([]) { $0.songsOfArtist(id) } }
    func songsOfGenre(_ genre: String) async -> [Song] { await read([]) { $0.songsOfGenre(genre) } }
    func albumsOfGenre(_ genre: String) async -> [Album] { await read([]) { $0.albumsOfGenre(genre) } }
    func starredSongs() async -> [Song] { await read([]) { $0.starredSongs() } }
    func starredAlbums() async -> [Album] { await read([]) { $0.starredAlbums() } }
    func starredArtists() async -> [Artist] { await read([]) { $0.starredArtists() } }
    func recentlyAdded(_ limit: Int) async -> [Album] { await read([]) { $0.recentlyAdded(limit) } }
    func mostPlayedSongs(_ limit: Int) async -> [Song] { await read([]) { $0.mostPlayedSongs(limit) } }
    func mostPlayedAlbums(_ limit: Int) async -> [Album] { await read([]) { $0.mostPlayedAlbums(limit) } }
    func mostPlayedArtists(_ limit: Int) async -> [Artist] { await read([]) { $0.mostPlayedArtists(limit) } }
    func history(_ limit: Int) async -> [HistoryEntry] { await read([]) { $0.recentHistory(limit) } }
    func randomAlbums(_ count: Int) async -> [Album] { await read([]) { $0.randomAlbums(count) } }
    func randomArtists(_ count: Int) async -> [Artist] { await read([]) { $0.randomArtists(count) } }
    func starredSongsNow() async -> [Song] { await starredSongs() }
    func allSongs() async -> [Song] { await read([]) { $0.allSongs() } }

    /** Playlists with their tracks resolved from the mirror, in playlist order. */
    func playlist(_ id: String) async -> PlaylistDetail? {
        await read(nil) { db in
            guard let row = db.playlist(id) else { return nil }
            return PlaylistDetail(playlist: row.playlist, songs: Self.inOrder(db, row.entryIds), entryIds: row.entryIds)
        }
    }

    /** Playlists ranked by how much their tracks get played. */
    func playlistsByPlays() async -> [Playlist] {
        await read([]) { db in
            let plays = Dictionary(db.mostPlayedSongs(5000).map { ($0.id, $0.playCount ?? 0) }, uniquingKeysWith: { a, _ in a })
            return db.playlists()
                .map { row in (row.playlist, row.entryIds.reduce(Int64(0)) { $0 + (plays[$1] ?? 0) }) }
                .filter { $0.1 > 0 }
                .sorted { $0.1 > $1.1 }
                .map { $0.0 }
        }
    }

    nonisolated private static func inOrder(_ db: LibraryDatabase, _ ids: [String]) -> [Song] {
        if ids.isEmpty { return [] }
        let found = Dictionary(db.songs(ids: ids).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { found[$0] }
    }

    func songsByIds(_ ids: [String]) async -> [Song] {
        await read([]) { Self.inOrder($0, ids) }
    }

    func songsOfAlbumNow(_ albumId: String) async -> [Song] {
        let local = await songsOfAlbum(albumId)
        if !local.isEmpty { return local }
        return (try? await client().getAlbum(albumId)?.song) ?? []
    }

    func songsOfArtistNow(_ artistId: String) async -> [Song] {
        let songs = await read([]) { $0.songsOfArtist(artistId) }
        return songs.sorted { a, b in
            if (a.year ?? 0) != (b.year ?? 0) { return (a.year ?? 0) > (b.year ?? 0) }
            if (a.album ?? "") != (b.album ?? "") { return (a.album ?? "") < (b.album ?? "") }
            if (a.discNumber ?? 1) != (b.discNumber ?? 1) { return (a.discNumber ?? 1) < (b.discNumber ?? 1) }
            return (a.track ?? 0) < (b.track ?? 0)
        }
    }

    func songsOfGenreNow(_ genre: String) async -> [Song] { await songsOfGenre(genre) }

    func randomSongs(_ count: Int, genre: String? = nil) async -> [Song] {
        let local = await read([Song]()) { db in
            genre.map { db.randomSongsOfGenre($0, count) } ?? db.randomSongs(count)
        }
        if !local.isEmpty { return local }
        return (try? await client().getRandomSongs(size: count, genre: genre)) ?? []
    }

    /** Tracks played most recently, newest first, without repeats. */
    func recentlyPlayed(_ limit: Int) async -> [Song] {
        let entries = await history(limit * 4)
        var seen = Set<String>()
        let ids = entries.map { $0.songId }.filter { seen.insert($0).inserted }.prefix(limit)
        return await songsByIds(Array(ids))
    }

    func search(_ query: String, limit: Int = 60) async -> SearchResults {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return SearchResults() }
        let pattern = "%\(q)%"
        let prefix = "\(q)%"
        return await read(SearchResults()) { db in
            SearchResults(
                artists: db.searchArtists(pattern, prefix, 20),
                albums: db.searchAlbums(pattern, prefix, 30),
                songs: db.searchSongs(pattern, prefix, limit)
            )
        }
    }

    /** The server's own search, for libraries that have not been synced (yet). */
    func searchServer(_ query: String) async throws -> SearchResults {
        let result = try await client().search3(query, artistCount: 20, albumCount: 30, songCount: 60)
        return SearchResults(artists: result.artist, albums: result.album, songs: result.song)
    }

    // ------------------------------------------------------- server extras --

    func artistInfo(_ id: String) async -> ArtistInfo? { try? await client().getArtistInfo2(id) }
    func topSongs(_ artistName: String) async -> [Song] { (try? await client().getTopSongs(artistName, count: 20)) ?? [] }
    func similarSongs(_ songId: String, count: Int = 50) async -> [Song] { (try? await client().getSimilarSongs2(songId, count: count)) ?? [] }

    func albumNotes(_ id: String) async -> String? {
        guard let notes = try? await client().getAlbumInfo2(id)?.notes,
              !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return notes
    }

    func radioStations() async throws -> [RadioStation] { try await client().getInternetRadioStations() }

    func lyrics(_ song: Song) async throws -> LyricsDoc? {
        let c = try client()
        // Older servers do not implement the OpenSubsonic extension.
        let structured = (try? await c.getLyricsBySongId(song.id)) ?? []
        var plain: Lyrics?
        if !structured.contains(where: { !($0.line ?? []).isEmpty }) {
            plain = try? await c.getLyrics(artist: song.artist, title: song.title)
        }
        return LyricsParser.choose(structured, plain: plain)
    }

    // ------------------------------------------------------------- actions --

    private func nowIso() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    /** Run a change; returns an error message, or nil. */
    private func attempt(_ body: () async throws -> Void) async -> String? {
        do {
            try await body()
            return nil
        } catch {
            return describeError(error)
        }
    }

    func setStarred(_ song: Song, _ starred: Bool) async -> String? {
        await attempt {
            let c = try client()
            if starred { try await c.star(id: song.id) } else { try await c.unstar(id: song.id) }
            try db?.setSongStarred(song.id, starred ? nowIso() : nil)
        }
    }

    func setStarred(_ songs: [Song], _ starred: Bool) async -> String? {
        await attempt {
            let c = try client()
            for chunk in songs.chunked(100) {
                for song in chunk {
                    if starred { try await c.star(id: song.id) } else { try await c.unstar(id: song.id) }
                }
                try db?.setSongsStarred(chunk.map { $0.id }, starred ? nowIso() : nil)
            }
        }
    }

    func setAlbumStarred(_ album: Album, _ starred: Bool) async -> String? {
        await attempt {
            let c = try client()
            if starred { try await c.star(albumId: album.id) } else { try await c.unstar(albumId: album.id) }
            try db?.setAlbumStarred(album.id, starred ? nowIso() : nil)
        }
    }

    func setArtistStarred(_ artist: Artist, _ starred: Bool) async -> String? {
        await attempt {
            let c = try client()
            if starred { try await c.star(artistId: artist.id) } else { try await c.unstar(artistId: artist.id) }
            try db?.setArtistStarred(artist.id, starred ? nowIso() : nil)
        }
    }

    func setRating(_ song: Song, _ rating: Int) async -> String? {
        await attempt {
            try await client().setRating(song.id, rating: rating)
            try db?.setSongRating(song.id, rating)
        }
    }

    func createPlaylist(_ name: String, _ songs: [Song]) async -> String? {
        await attempt {
            try await client().createPlaylist(name: name.trimmingCharacters(in: .whitespaces), songIds: songs.map { $0.id })
            try await refreshPlaylistsNow()
        }
    }

    func addToPlaylist(_ playlistId: String, _ songs: [Song]) async -> String? {
        await attempt {
            for chunk in songs.chunked(200) {
                try await client().updatePlaylist(playlistId, songIdToAdd: chunk.map { $0.id })
            }
            try await refreshPlaylistNow(playlistId)
        }
    }

    func removeFromPlaylist(_ playlistId: String, _ indices: [Int]) async -> String? {
        await attempt {
            try await client().updatePlaylist(playlistId, songIndexToRemove: indices.sorted(by: >))
            try await refreshPlaylistNow(playlistId)
        }
    }

    func renamePlaylist(_ playlistId: String, _ name: String) async -> String? {
        await attempt {
            try await client().updatePlaylist(playlistId, name: name.trimmingCharacters(in: .whitespaces))
            try await refreshPlaylistNow(playlistId)
        }
    }

    func deletePlaylist(_ playlistId: String) async -> String? {
        await attempt {
            try await client().deletePlaylist(playlistId)
            try await refreshPlaylistsNow()
        }
    }

    /** Re-read the playlist list (and every playlist's tracks) from the server. */
    func refreshPlaylists() async -> String? { await attempt { try await refreshPlaylistsNow() } }

    func refreshPlaylist(_ playlistId: String) async -> String? { await attempt { try await refreshPlaylistNow(playlistId) } }

    private func refreshPlaylistsNow() async throws {
        guard let db else { return }
        let c = try client()
        var playlists: [Playlist] = []
        for summary in try await c.getPlaylists() {
            playlists.append((try? await c.getPlaylist(summary.id)) ?? summary)
        }
        for playlist in playlists {
            if let entries = playlist.entry, !entries.isEmpty { try db.upsertSongs(entries) }
        }
        try db.replacePlaylists(playlists)
    }

    private func refreshPlaylistNow(_ playlistId: String) async throws {
        guard let db else { return }
        guard let fresh = try await client().getPlaylist(playlistId) else { return }
        let position = db.playlists().firstIndex(where: { $0.playlist.id == playlistId }) ?? Int.max / 2
        if let entries = fresh.entry {
            for chunk in entries.chunked(SQL_CHUNK) { try db.upsertSongs(chunk) }
        }
        try db.upsertPlaylist(fresh, position: position, entryIds: fresh.entry?.map { $0.id } ?? [])
    }

    func clearHistory() async {
        try? db?.clearHistory()
    }

    /** Clear the synced library, analysis and history; downloads stay. */
    func clearLibraryData() async {
        guard let db else { return }
        try? db.clearLibrary()
        try? db.clearAnalysis()
        try? db.clearHistory()
        try? db.putMeta("syncState", "{}")
    }
}

/**
 * Collects database change notifications from any thread and delivers them
 * on the main thread at most four times a second — a sync writes thousands
 * of rows, and every screen does not need to reload for each one.
 */
final class ChangeCoalescer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Set<LibraryChange>()
    private var scheduled = false
    @MainActor var onFlush: ((Set<LibraryChange>) -> Void)?

    func note(_ changes: Set<LibraryChange>) {
        lock.lock()
        pending.formUnion(changes)
        let schedule = !scheduled
        scheduled = true
        lock.unlock()
        guard schedule else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [self] in
            lock.lock()
            let batch = pending
            pending = []
            scheduled = false
            lock.unlock()
            MainActor.assumeIsolated { onFlush?(batch) }
        }
    }
}
