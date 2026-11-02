import ActivityKit
import Foundation

/**
 * The Live Activity KultrPre 1.4.2 to 1.4.5 showed. It is gone; the type
 * stays only so the app can end one those builds left running.
 */
struct NowPlayingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var songId: String
        var title: String
        var artist: String
        var isPlaying: Bool
        /** When the track began, as if it had played without a pause. */
        var startedAt: Date
        var durationMs: Int64
        /** Where the track is, for the bar while paused. */
        var positionMs: Int64
        /** The next track's title, if there is one. */
        var next: String?
        /** When the mix into [next] begins. */
        var mixAt: Date?
        /** The kind of mix, like "Beat-matched blend" or "Crossfade". */
        var mix: String?
        /** The station playing, if one is. */
        var station: String?

        var endsAt: Date { startedAt.addingTimeInterval(Double(max(durationMs, 1)) / 1000) }
        var progress: Double { durationMs > 0 ? min(1, max(0, Double(positionMs) / Double(durationMs))) : 0 }
    }
}
