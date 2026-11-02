import ActivityKit
import Foundation

/**
 * The Live Activity on the Lock Screen and in the Dynamic Island: what is
 * playing, and when InjeKt mixes into what comes next. The app starts and
 * updates it; the widget extension draws it. Clocks run by themselves from
 * the dates in here, so it only changes when the music does.
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
