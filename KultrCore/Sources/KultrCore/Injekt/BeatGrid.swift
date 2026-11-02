import Foundation

/**
 * The downbeats InjeKt found in a track: the first beat of each bar, every
 * four beats from [TrackAnalysis.downbeatOffset]. Used for the beat pulse.
 */
struct BeatGrid: Equatable {
    /** Seconds of the first downbeat. */
    let offset: Double
    /** Seconds per bar. */
    let bar: Double

    /** Nil when the tempo is too uncertain to pulse along with. */
    init?(_ analysis: TrackAnalysis) {
        guard analysis.bpm >= 40, analysis.bpm <= 240, analysis.bpmConfidence >= 0.3 else { return nil }
        offset = analysis.downbeatOffset
        bar = 4 * 60 / analysis.bpm
    }

    /** Seconds since the last downbeat at [seconds] into the track; before the first one, how long until it, negative. */
    func sinceDownbeat(_ seconds: Double) -> Double {
        let since = seconds - offset
        guard since >= 0 else { return since }
        return since - floor(since / bar) * bar
    }

    /** Seconds from [seconds] to the next downbeat. */
    func untilDownbeat(_ seconds: Double) -> Double {
        let since = sinceDownbeat(seconds)
        return since < 0 ? -since : bar - since
    }

    /** How far the pulse has come back down, 1 right on a downbeat fading to 0 within a quarter of a second. */
    func pulse(_ seconds: Double) -> Double {
        let since = sinceDownbeat(seconds)
        guard since >= 0 else { return 0 }
        return exp(-since / 0.09)
    }
}
