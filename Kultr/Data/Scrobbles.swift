import Foundation

/**
 * Listening history and scrobbling.
 *
 * Every play that reaches half the track (or four minutes) is written to the
 * local history, which feeds the Stats page, and sent to the server. Plays
 * made offline are kept and sent the next time the server is reachable.
 */
@MainActor
final class Scrobbles {
    private unowned let graph: AppGraph
    private var flushing = false

    init(graph: AppGraph) {
        self.graph = graph
    }

    /** Tell the server what is playing right now. Best-effort. */
    func nowPlaying(_ song: Song) {
        guard !song.isRadio, graph.settings.current.scrobble, let client = graph.auth.client else { return }
        Task.detached { try? await client.scrobble(song.id, submission: false) }
    }

    /** A play counted: record it, bump the local play count, and submit it. */
    func played(_ song: Song, seconds: Int, completed: Bool, source: String) {
        guard !song.isRadio, let db = graph.library.db else { return }
        let scrobble = graph.settings.current.scrobble
        let client = graph.auth.client
        Task.detached {
            let playedAt = Format.nowMs()
            let id = try? db.insertHistory(
                HistoryEntry(songId: song.id, playedAt: playedAt, seconds: seconds, completed: completed, source: source, submitted: !scrobble)
            )
            try? db.bumpPlayCount(song.id, played: ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: Double(playedAt) / 1000)))
            guard scrobble, let client, let id else { return }
            do {
                try await client.scrobble(song.id, submission: true, timeMs: playedAt)
                try? db.markSubmitted(id)
            } catch {
                // Offline: flush() sends it later.
            }
        }
    }

    /** Send plays that could not be submitted when they happened. */
    func flush() async {
        guard graph.settings.current.scrobble, !flushing, let db = graph.library.db, let client = graph.auth.client else { return }
        flushing = true
        defer { flushing = false }
        await Task.detached {
            for entry in db.unsubmittedHistory(200) {
                do {
                    try await client.scrobble(entry.songId, submission: true, timeMs: entry.playedAt)
                    try? db.markSubmitted(entry.id)
                } catch {
                    break
                }
            }
        }.value
    }
}
