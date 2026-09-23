import Foundation

enum SyncMode: Hashable {
    case full, check
}

enum SyncPhase: Hashable {
    case idle, connecting, artists, albums, songs, playlists, genres, cleanup, done, error, cancelled
}

struct SyncProgress: Hashable {
    let phase: SyncPhase
    let message: String
    let current: Int
    let total: Int
    /** 0..1 across the whole run, so a single progress bar can show it. */
    let percent: Double
}

struct LibraryCounts: Codable, Hashable {
    var artists: Int = 0
    var albums: Int = 0
    var songs: Int = 0
    var playlists: Int = 0
    var genres: Int = 0
}

struct SyncState: Codable, Hashable {
    var lastFullSync: Int64?
    var lastCheck: Int64?
    var counts: LibraryCounts = LibraryCounts()
    var serverVersion: String?
    var serverType: String?
    /** Newest album `created` timestamp seen, used for cheap delta checks. */
    var newestAlbumCreated: String?

    init(
        lastFullSync: Int64? = nil,
        lastCheck: Int64? = nil,
        counts: LibraryCounts = LibraryCounts(),
        serverVersion: String? = nil,
        serverType: String? = nil,
        newestAlbumCreated: String? = nil
    ) {
        self.lastFullSync = lastFullSync
        self.lastCheck = lastCheck
        self.counts = counts
        self.serverVersion = serverVersion
        self.serverType = serverType
        self.newestAlbumCreated = newestAlbumCreated
    }

    enum CodingKeys: String, CodingKey {
        case lastFullSync, lastCheck, counts, serverVersion, serverType, newestAlbumCreated
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastFullSync = c.int64(.lastFullSync)
        lastCheck = c.int64(.lastCheck)
        counts = (try? c.decodeIfPresent(LibraryCounts.self, forKey: .counts)) ?? LibraryCounts()
        serverVersion = c.string(.serverVersion)
        serverType = c.string(.serverType)
        newestAlbumCreated = c.string(.newestAlbumCreated)
    }
}

struct SyncSummary: Hashable {
    let mode: SyncMode
    let startedAt: Int64
    let finishedAt: Int64
    let counts: LibraryCounts
    let albumsAdded: Int
    let albumsUpdated: Int
    let albumsRemoved: Int
    let songsRemoved: Int
    let upToDate: Bool
    let errors: [String]
}

/** What an album looked like last time, to decide whether its tracks need re-reading. */
struct AlbumStamp: Hashable {
    let songCount: Int?
    let changed: String?
    let duration: Int?
}

/**
 * Where the mirrored library lives. On iOS this is SQLite; in tests, maps.
 * Implementations should make each call atomic.
 */
protocol LibraryStore: AnyObject {
    func albumStamps() async throws -> [String: AlbumStamp]
    func putArtists(_ artists: [Artist]) async throws
    func putAlbums(_ albums: [Album]) async throws

    /**
     * Store the full track list of each album, removing tracks that belong to
     * one of these albums but are no longer on it.
     */
    func replaceAlbumSongs(_ songsByAlbum: [String: [Song]]) async throws
    func replacePlaylists(_ playlists: [Playlist]) async throws
    func replaceGenres(_ genres: [Genre]) async throws
    func deleteAlbumsNotIn(_ keep: Set<String>) async throws -> Int
    func deleteArtistsNotIn(_ keep: Set<String>) async throws -> Int

    /** Remove songs whose album is not in [albumIds]. */
    func deleteSongsOutsideAlbums(_ albumIds: Set<String>) async throws -> Int
    func counts() async throws -> LibraryCounts
    func syncState() async throws -> SyncState
    func setSyncState(_ state: SyncState) async throws
}

/** Shared bookkeeping for the parallel track readers. */
private final class SongBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [String: [Song]] = [:]
    private var buffered = 0
    private var cursor = 0
    private(set) var processed = 0
    private(set) var songsSeen = 0
    private(set) var errors: [String] = []

    func nextIndex() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let value = cursor
        cursor += 1
        return value
    }

    /** Add an album's tracks; true when enough has piled up to write. */
    func add(_ albumId: String, _ songs: [Song]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        buffer[albumId] = songs
        buffered += songs.count
        songsSeen += songs.count
        return buffered >= 400
    }

    func take() -> [String: [Song]] {
        lock.lock()
        defer { lock.unlock() }
        let copy = buffer
        buffer = [:]
        buffered = 0
        return copy
    }

    func fail(_ message: String) {
        lock.lock()
        errors.append(message)
        lock.unlock()
    }

    func finishOne() -> (done: Int, seen: Int) {
        lock.lock()
        defer { lock.unlock() }
        processed += 1
        return (processed, songsSeen)
    }
}

/**
 * Mirror the server's library into a [LibraryStore].
 *
 * [SyncMode.full] re-reads every album's track list: slow but exhaustive.
 * [SyncMode.check] re-reads the album index (cheap) and only pulls tracks for
 * albums that are new or whose `changed`/`songCount`/`duration` moved.
 */
final class LibrarySync {
    private static let albumPage = 500
    private static let wArtists = 0.05
    private static let wAlbums = 0.15
    private static let wSongs = 0.65
    private static let wPlaylists = 0.10
    private static let wGenres = 0.05

    private let client: SubsonicClient
    private let store: LibraryStore
    private let clock: () -> Int64

    init(client: SubsonicClient, store: LibraryStore, clock: @escaping () -> Int64 = { Format.nowMs() }) {
        self.client = client
        self.store = store
        self.clock = clock
    }

    func run(
        mode: SyncMode,
        includePlaylistContents: Bool = true,
        concurrency: Int = 6,
        onProgress: @escaping (SyncProgress) -> Void = { _ in }
    ) async throws -> SyncSummary {
        let workers = min(12, max(1, concurrency))
        let startedAt = clock()
        var errors: [String] = []
        var base = 0.0
        func emit(_ phase: SyncPhase, _ message: String, _ current: Int, _ total: Int, _ weight: Double) {
            let fraction = total > 0 ? min(1, Double(current) / Double(total)) : 0
            onProgress(SyncProgress(phase: phase, message: message, current: current, total: total, percent: min(1, base + fraction * weight)))
        }

        do {
            emit(.connecting, "Contacting your server…", 0, 1, 0)
            let info = try await client.ping()

            // ------------------------------------------------------ artists --
            emit(.artists, "Reading artists…", 0, 1, Self.wArtists)
            let artists = try await client.getArtists()
            try await store.putArtists(artists)
            emit(.artists, "\(Format.number(artists.count)) artists", 1, 1, Self.wArtists)
            base += Self.wArtists

            // ------------------------------------------------------- albums --
            emit(.albums, "Reading albums…", 0, 1, Self.wAlbums)
            var albums: [Album] = []
            var offset = 0
            while true {
                try Task.checkCancellation()
                let page = try await client.getAlbumList2(.alphabeticalByName, size: Self.albumPage, offset: offset)
                albums += page
                emit(.albums, "Reading albums… \(Format.number(albums.count))", albums.count, albums.count + Self.albumPage, Self.wAlbums)
                if page.count < Self.albumPage { break }
                offset += Self.albumPage
                // A misbehaving server that always returns a full page must not spin forever.
                if offset > 400_000 { break }
            }
            let previous = try await store.albumStamps()
            try await store.putAlbums(albums)
            base += Self.wAlbums

            // -------------------------------------------------------- songs --
            let stale = albums.filter { album in
                if mode == .full { return true }
                guard let before = previous[album.id] else { return true }
                return before.songCount != album.songCount || before.changed != album.changed || before.duration != album.duration
            }
            let albumsAdded = albums.filter { previous[$0.id] == nil }.count
            let albumsUpdated = max(0, stale.count - albumsAdded)

            emit(.songs, stale.isEmpty ? "Tracks already up to date" : "Reading tracks…", 0, max(1, stale.count), Self.wSongs)
            let shared = SongBuffer()
            let client = self.client
            let store = self.store
            let songsBase = base
            let total = stale.count
            let report: (Int, Int) -> Void = { done, seen in
                if done % 5 == 0 || done == total {
                    let fraction = min(1, Double(done) / Double(max(1, total)))
                    onProgress(
                        SyncProgress(
                            phase: .songs,
                            message: "Reading tracks… \(Format.number(seen)) from \(Format.number(done))/\(Format.number(total)) albums",
                            current: done,
                            total: max(1, total),
                            percent: min(1, songsBase + fraction * LibrarySync.wSongs)
                        )
                    )
                }
            }
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<min(workers, max(1, stale.count)) {
                    group.addTask {
                        while true {
                            try Task.checkCancellation()
                            let i = shared.nextIndex()
                            if i >= stale.count { break }
                            let album = stale[i]
                            do {
                                let detail = try await client.getAlbum(album.id)
                                if shared.add(album.id, detail?.song ?? []) {
                                    let batch = shared.take()
                                    if !batch.isEmpty { try await store.replaceAlbumSongs(batch) }
                                }
                            } catch is CancellationError {
                                throw CancellationError()
                            } catch {
                                shared.fail("\(album.name): \(describeError(error))")
                            }
                            let progress = shared.finishOne()
                            report(progress.done, progress.seen)
                        }
                    }
                }
                try await group.waitForAll()
            }
            let rest = shared.take()
            if !rest.isEmpty { try await store.replaceAlbumSongs(rest) }
            errors += shared.errors
            base += Self.wSongs

            // ---------------------------------------------------- playlists --
            emit(.playlists, "Reading playlists…", 0, 1, Self.wPlaylists)
            var playlists = try await client.getPlaylists()
            if includePlaylistContents && !playlists.isEmpty {
                var detailed = playlists
                for (i, playlist) in playlists.enumerated() {
                    try Task.checkCancellation()
                    do {
                        if let full = try await client.getPlaylist(playlist.id) { detailed[i] = full }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        errors.append("Playlist \(playlist.name): \(describeError(error))")
                    }
                    emit(.playlists, "Reading playlists… \(i + 1)/\(playlists.count)", i + 1, playlists.count, Self.wPlaylists)
                }
                playlists = detailed
            }
            try await store.replacePlaylists(playlists)
            base += Self.wPlaylists

            // ------------------------------------------------------- genres --
            emit(.genres, "Reading genres…", 0, 1, Self.wGenres)
            try await store.replaceGenres(try await client.getGenres())
            base += Self.wGenres

            // ------------------------------------------------------ cleanup --
            emit(.cleanup, "Tidying up…", 1, 1, 0)
            let albumIds = Set(albums.map { $0.id })
            let albumsRemoved = try await store.deleteAlbumsNotIn(albumIds)
            _ = try await store.deleteArtistsNotIn(Set(artists.map { $0.id }))
            let songsRemoved = try await store.deleteSongsOutsideAlbums(albumIds)

            let counts = try await store.counts()
            let newest = albums.compactMap { $0.created }.max()
            let before = try await store.syncState()
            try await store.setSyncState(
                SyncState(
                    lastFullSync: mode == .full ? startedAt : before.lastFullSync,
                    lastCheck: startedAt,
                    counts: counts,
                    serverVersion: info.serverVersion ?? info.version,
                    serverType: info.type,
                    newestAlbumCreated: newest
                )
            )
            onProgress(SyncProgress(phase: .done, message: "Library up to date", current: 1, total: 1, percent: 1))
            return SyncSummary(
                mode: mode,
                startedAt: startedAt,
                finishedAt: clock(),
                counts: counts,
                albumsAdded: albumsAdded,
                albumsUpdated: albumsUpdated,
                albumsRemoved: albumsRemoved,
                songsRemoved: songsRemoved,
                upToDate: mode == .check && albumsAdded == 0 && albumsUpdated == 0 && albumsRemoved == 0,
                errors: errors
            )
        } catch is CancellationError {
            onProgress(SyncProgress(phase: .cancelled, message: "Sync cancelled", current: 0, total: 1, percent: 0))
            throw CancellationError()
        } catch {
            onProgress(SyncProgress(phase: .error, message: describeError(error), current: 0, total: 1, percent: 0))
            throw error
        }
    }

    struct QuickCheck: Hashable {
        let changed: Bool
        let reason: String
    }

    /**
     * Cheap "does the server have anything new?" probe — two requests, no
     * writes. Used for the periodic background check.
     */
    func quickCheck() async throws -> QuickCheck {
        let state = try await store.syncState()
        let newest = try await client.getAlbumList2(.newest, size: 1).first?.created
        if let newest, let known = state.newestAlbumCreated, newest > known {
            return QuickCheck(changed: true, reason: "New albums were added to your server.")
        }
        if newest != nil && state.newestAlbumCreated == nil {
            return QuickCheck(changed: true, reason: "The library on this phone has never been synced.")
        }
        do {
            let scan = try await client.getScanStatus()
            if let count = scan.count, state.counts.songs > 0, count != Int64(state.counts.songs) {
                return QuickCheck(
                    changed: true,
                    reason: "Server reports \(Format.number(Int(count))) tracks, this phone has \(Format.number(state.counts.songs))."
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // getScanStatus needs admin rights on some setups; ignore.
        }
        return QuickCheck(changed: false, reason: "Everything matches.")
    }
}
