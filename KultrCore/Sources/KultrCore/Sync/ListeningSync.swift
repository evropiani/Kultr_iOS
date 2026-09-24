import Foundation

/**
 * Listening data, read back from the server.
 *
 * Navidrome keeps what matters across devices: each track's play count and
 * when it was last played, fed by scrobbles from every client. Albums come
 * back with their own play count and last-played time, so an album whose
 * numbers moved since the mirror last saw it was played somewhere (here or
 * on another device), and re-reading its tracks brings their counts and
 * times up to date. The server lists albums most recently played first, so
 * a pull stops at the first page that reaches plays it has already seen.
 */
final class ListeningSync {
    struct Pull: Hashable {
        let albumsChanged: Int
        let songsRefreshed: Int
    }

    static let page = 100
    static let maxPages = 5
    static let maxAlbums = 120
    static let workers = 3

    private let client: SubsonicClient
    private let store: LibraryStore

    init(client: SubsonicClient, store: LibraryStore) {
        self.client = client
        self.store = store
    }

    func pull() async throws -> Pull {
        let watermark = try await store.syncState().listeningPulledThrough ?? ""
        let stamps = try await store.albumStamps()
        var newest = watermark
        var changed: [Album] = []

        for page in 0..<Self.maxPages {
            let albums = try await client.getAlbumList2(.recent, size: Self.page, offset: page * Self.page)
            for album in albums {
                if let played = album.played, played > newest { newest = played }
                // Albums the mirror does not have yet are the library sync's job.
                guard let local = stamps[album.id] else { continue }
                if local.playsDiffer(album) { changed.append(album) }
            }
            let oldest = albums.last?.played
            if albums.count < Self.page { break }
            if !watermark.isEmpty, let oldest, oldest <= watermark { break }
        }

        let work = Array(changed.prefix(Self.maxAlbums))
        let queue = WorkQueue(work)
        let client = self.client
        let store = self.store
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<min(Self.workers, max(1, work.count)) {
                group.addTask {
                    var refreshed = 0
                    while let album = queue.next() {
                        try Task.checkCancellation()
                        do {
                            let songs = try await client.getAlbum(album.id)?.song ?? []
                            try await store.replaceAlbumSongs([album.id: songs])
                            try await store.putAlbums([album])
                            refreshed += songs.count
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            // Left for next time: its stamp still differs.
                        }
                    }
                    return refreshed
                }
            }
            for try await count in group { queue.add(count) }
        }

        if newest != watermark {
            var state = try await store.syncState()
            state.listeningPulledThrough = newest
            try await store.setSyncState(state)
        }
        return Pull(albumsChanged: changed.count, songsRefreshed: queue.total)
    }
}

/** Albums handed out one at a time to the parallel readers. */
private final class WorkQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Album]
    private var cursor = 0
    private(set) var total = 0

    init(_ items: [Album]) {
        self.items = items
    }

    func next() -> Album? {
        lock.lock()
        defer { lock.unlock() }
        guard cursor < items.count else { return nil }
        defer { cursor += 1 }
        return items[cursor]
    }

    func add(_ count: Int) {
        lock.lock()
        total += count
        lock.unlock()
    }
}
