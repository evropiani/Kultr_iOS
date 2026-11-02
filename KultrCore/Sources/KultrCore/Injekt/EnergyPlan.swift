import Foundation

/** The shape of a set: energy from 0 to 1 at evenly spaced points from its start to its end. */
struct EnergyCurve: Codable, Hashable {
    var points: [Double]

    init(_ points: [Double]) {
        self.points = points.count >= 2 ? points.map { min(1, max(0, $0)) } : [0.5, 0.5]
    }

    /** Where the line is at [fraction] (0 to 1) of the set. */
    func value(at fraction: Double) -> Double {
        let f = min(1, max(0, fraction)) * Double(points.count - 1)
        let i = min(points.count - 2, Int(f))
        let t = f - Double(i)
        return points[i] * (1 - t) + points[i + 1] * t
    }

    /** The same shape with [count] points, for drawing over. */
    func resampled(_ count: Int) -> EnergyCurve {
        EnergyCurve((0..<max(2, count)).map { value(at: Double($0) / Double(max(1, count - 1))) })
    }

    static let warmUpAndPeak = EnergyCurve([0.35, 0.5, 0.65, 0.8, 0.95, 0.9, 0.7, 0.5])
    static let steady = EnergyCurve([0.6, 0.6])
    static let build = EnergyCurve([0.3, 0.95])
    static let windDown = EnergyCurve([0.7, 0.45, 0.25, 0.15])
}

/** One track of a planned set: when it starts, and the energy the line asked for there. */
struct PlannedTrack: Hashable {
    let song: Song
    let energy: Double
    let target: Double
    /** Seconds from the start of the set. */
    let startsAt: Double
}

/** How well [b] mixes out of [a]: close tempo (or half or double) and a neighbouring key. */
func mixScore(_ a: TrackAnalysis, _ b: TrackAnalysis) -> Double {
    let ratio = a.bpm > 0 && b.bpm > 0 ? b.bpm / a.bpm : 1
    let tempoDistance = min(abs(ratio - 1), abs(ratio - 2) / 2, abs(ratio - 0.5) * 2)
    let tempo = exp(-tempoDistance * 10)
    let key = 1 - min(1, camelotDistance(a.camelot, b.camelot) / 6)
    return tempo * 0.6 + key * 0.4
}

/**
 * A set of about [minutes] that follows [curve]: each next track is the one
 * whose energy is closest to where the line is at that moment, that mixes
 * well out of the one before (tempo and key), isn't by the same artist as it
 * and hasn't been used. Mixes overlap by [overlap] seconds.
 */
func planSet<R: RandomNumberGenerator>(
    curve: EnergyCurve,
    minutes: Int,
    candidates: [(Song, TrackAnalysis)],
    overlap: Double = 8,
    random: inout R
) -> [PlannedTrack] {
    let total = Double(max(1, minutes) * 60)
    var used = Set<String>()
    var elapsed = 0.0
    var previous: (Song, TrackAnalysis)?
    var out: [PlannedTrack] = []
    let usable = candidates.filter { $0.1.duration >= 60 && !$0.0.isRadio }
    while elapsed < total && out.count < 300 {
        let target = curve.value(at: elapsed / total)
        var best: (Song, TrackAnalysis)?
        var bestScore = -Double.infinity
        for candidate in usable where !used.contains(candidate.0.id) {
            let fit = 1 - min(1, abs(candidate.1.energy - target) * 3)
            var score = fit * 0.65 + (previous.map { mixScore($0.1, candidate.1) } ?? 1) * 0.35
            if let previous, previous.0.artistId != nil, previous.0.artistId == candidate.0.artistId { score *= 0.7 }
            score += Double.random(in: 0..<0.04, using: &random)
            if score > bestScore {
                bestScore = score
                best = candidate
            }
        }
        guard let best else { break }
        used.insert(best.0.id)
        out.append(PlannedTrack(song: best.0, energy: best.1.energy, target: target, startsAt: elapsed))
        elapsed += max(30, best.1.duration - overlap)
        previous = best
    }
    return out
}
