import Foundation

/**
 * Listening history, and sending plays to the server.
 *
 * Every play that reaches half the track (or four minutes) is written to the
 * local history as waiting (`submitted = false`) and sent to the server with
 * the time it actually happened. If the server cannot be reached it stays
 * waiting and goes out later, still with its original time, and exactly
 * once: a play being sent is never picked up by a flush at the same moment.
 * Navidrome counts the plays, so every device (and this one, after a fresh
 * sync) sees the same "recently" and "most played".
 */
@MainActor
final class Scrobbles {
    /** Subsonic's "the requested data was not found". */
    nonisolated private static let notFound = 70

    private unowned let graph: AppGraph
    private var flushing = false
    /** History entries being sent right now. */
    private var inFlight: Set<Int64> = []

    init(graph: AppGraph) {
        self.graph = graph
    }

    /** Tell the server what is playing right now. Best-effort. */
    func nowPlaying(_ song: Song) {
        guard !song.isRadio, graph.settings.current.scrobble, let client = graph.auth.client else { return }
        Task.detached { try? await client.scrobble(song.id, submission: false) }
    }

    /** A play counted: record it, bump the local play count, and send it. Internet radio is not a library track and is not sent. */
    func played(_ song: Song, seconds: Int, completed: Bool, source: String) {
        guard !song.isRadio, let db = graph.library.db else { return }
        let sending = graph.settings.current.scrobble
        let playedAt = Format.nowMs()
        let entry = HistoryEntry(songId: song.id, playedAt: playedAt, seconds: seconds, completed: completed, source: source, submitted: !sending)
        // Recorded and claimed here on the main actor, so a flush cannot send it too.
        guard let id = try? db.insertHistory(entry) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: Double(playedAt) / 1000))
        try? db.bumpPlayCount(song.id, played: stamp)
        guard sending, let client = graph.auth.client else { return }
        inFlight.insert(id)
        Task {
            defer { inFlight.remove(id) }
            // Offline: flush() sends it later, with the time it was played.
            _ = try? await Self.send(client, db, id, song.id, playedAt)
        }
    }

    /** Send plays that could not be sent when they happened. Returns how many went. */
    @discardableResult
    func flush() async -> Int {
        guard graph.settings.current.scrobble, !flushing, let db = graph.library.db, let client = graph.auth.client else { return 0 }
        flushing = true
        defer { flushing = false }
        let waiting = await Task.detached { db.unsubmittedHistory(200) }.value
        var sent = 0
        for entry in waiting where !inFlight.contains(entry.id) {
            inFlight.insert(entry.id)
            defer { inFlight.remove(entry.id) }
            do {
                try await Self.send(client, db, entry.id, entry.songId, entry.playedAt)
                sent += 1
            } catch {
                // Still unreachable: keep the rest queued and try again later.
                break
            }
        }
        return sent
    }

    /**
     * Scrobble one play and mark it sent. A server that answers but cannot
     * find the track (it was deleted) will never accept it, so that play is
     * let go instead of blocking the queue forever; anything else throws and
     * the play stays waiting.
     */
    nonisolated private static func send(_ client: SubsonicClient, _ db: LibraryDatabase, _ id: Int64, _ songId: String, _ playedAt: Int64) async throws {
        do {
            try await client.scrobble(songId, submission: true, timeMs: playedAt)
        } catch let error as SubsonicError where error.code == notFound {
            // Gone from the server: nothing to count it against.
        }
        try db.markSubmitted(id)
    }
}
