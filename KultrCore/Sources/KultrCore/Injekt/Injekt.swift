import Foundation

/*
 * InjeKt — Kultr's DJ-style transition engine.
 *
 * Given the track that is playing and the track that comes next, the planner
 * decides *where* to start the blend, *how long* it should last, whether the
 * two tracks can be beat-matched, and which tricks to use (bass swap, filter
 * sweep, intro skip). The playback engine then just executes the plan.
 *
 * Everything degrades gracefully: with no analysis available it produces a
 * plain equal-power crossfade, and with crossfade switched off entirely it
 * produces a gapless hand-off.
 */

enum TransitionType: String, Hashable {
    case gapless, crossfade, blend, sweep, cut
}

struct TransitionPlan: Hashable {
    var type: TransitionType
    /** Length of the overlap in seconds (wall clock). */
    var duration: Double
    /** Position in the outgoing track at which the overlap begins, seconds. */
    var startAt: Double
    /** Position in the incoming track to start from, seconds. */
    var inStartOffset: Double
    /** Playback rate the incoming track starts at, for beat-matching, and keeps. */
    var incomingRate: Double
    /** Rate the outgoing track plays at: whatever an earlier blend left it at. */
    var outgoingRate: Double
    var bassSwap: Bool
    var sweep: Bool
    var curve: CrossfadeCurve
    /** Short label for the UI, e.g. "InjeKt · 124⇄126 @ 125 BPM · 8 bars". */
    var label: String
    /** Longer explanation, shown in the InjeKt panel. */
    var reason: String
}

private let MIN_TRANSITION = 2.0
private let MAX_TRANSITION = 24.0

private func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
    min(high, max(low, value))
}

private func fmt(_ value: Double, _ digits: Int = 0) -> String {
    String(format: "%.\(digits)f", value)
}

/** Pick whichever downbeat anchor was fitted closest to [time]. */
private func barOrigin(_ analysis: TrackAnalysis, _ time: Double) -> Double {
    let head = analysis.downbeatOffset
    let tail = analysis.outroDownbeat
    return abs(time - tail) < abs(time - head) ? tail : head
}

/** Round [time] down to the nearest bar boundary of [analysis]'s grid. */
func snapDownToBar(_ analysis: TrackAnalysis, _ time: Double) -> Double {
    let bar = 60 / analysis.bpm * 4
    if !bar.isFinite || bar <= 0 { return time }
    let origin = barOrigin(analysis, time)
    let bars = floor((time - origin) / bar)
    return max(0, origin + bars * bar)
}

/** First bar boundary at or after [time]. */
func snapUpToBar(_ analysis: TrackAnalysis, _ time: Double) -> Double {
    let bar = 60 / analysis.bpm * 4
    if !bar.isFinite || bar <= 0 { return time }
    let origin = barOrigin(analysis, time)
    let bars = ceil((time - origin) / bar)
    return max(0, origin + bars * bar)
}

/**
 * The speed the incoming track (at [bpmB]) needs to play at to match the
 * outgoing one (at [bpmA]), counting its half and double time, and how far
 * that shifts it, as a fraction. A shift of infinity means no match at all.
 */
func matchTempo(_ bpmA: Double, _ bpmB: Double) -> (rate: Double, shift: Double) {
    var best = (rate: 1.0, shift: Double.infinity)
    if !(bpmA > 0) || !(bpmB > 0) { return best }
    for target in [bpmB, bpmB * 2, bpmB / 2] where target >= 50 && target <= 220 {
        let rate = bpmA / target
        if abs(rate - 1) < best.shift { best = (rate, abs(rate - 1)) }
    }
    return best
}

func gaplessPlan(_ durationA: Double) -> TransitionPlan {
    TransitionPlan(
        type: .gapless, duration: 0, startAt: max(0, durationA), inStartOffset: 0,
        incomingRate: 1, outgoingRate: 1,
        bassSwap: false, sweep: false, curve: .linear,
        label: "Gapless",
        reason: "Tracks run straight into each other with no silence between them."
    )
}

/** No overlap at all: the next track begins when this one has finished. */
func hardCutPlan(_ durationA: Double) -> TransitionPlan {
    TransitionPlan(
        type: .cut, duration: 0, startAt: max(0, durationA), inStartOffset: 0,
        incomingRate: 1, outgoingRate: 1,
        bassSwap: false, sweep: false, curve: .linear,
        label: "No crossfade",
        reason: "Crossfade and gapless are both off, so tracks simply follow one another."
    )
}

func crossfadePlan(_ durationA: Double, seconds: Double, curve: CrossfadeCurve) -> TransitionPlan {
    let duration = clamp(min(seconds, durationA * 0.4), 0.2, MAX_TRANSITION)
    let shown = fmt(duration, 1)
    return TransitionPlan(
        type: .crossfade, duration: duration, startAt: max(0, durationA - duration), inStartOffset: 0,
        incomingRate: 1, outgoingRate: 1,
        bassSwap: false, sweep: false, curve: curve,
        label: "Crossfade · \(shown)s",
        reason: "The outgoing track fades out over \(shown) seconds while the next one fades in."
    )
}

struct PlanContext: Hashable {
    /** Real duration of the outgoing track, seconds. */
    var durationA: Double
    /** Where playback currently is, so a plan is never scheduled in the past. */
    var currentTime: Double
    /** The speed the outgoing track is playing at now (1 unless an earlier blend left it matched). */
    var outgoingRate: Double = 1
}

/**
 * Build the transition from [current] to [next]. Pure: the caller supplies
 * analysis for both tracks (or nil when there is none).
 */
func planTransition(
    current: Song,
    next: Song,
    context: PlanContext,
    settings s: Settings,
    analysisA: TrackAnalysis?,
    analysisB: TrackAnalysis?
) -> TransitionPlan {
    let durationA = context.durationA > 0 ? context.durationA : Double(current.duration ?? 0)

    // Streams without a length (radio) cannot be planned; let them end.
    if durationA <= 0 || current.isRadio || next.isRadio { return hardCutPlan(durationA) }

    if !s.injektEnabled {
        if !s.crossfadeEnabled || s.crossfadeSeconds <= 0 {
            return s.gapless ? gaplessPlan(durationA) : hardCutPlan(durationA)
        }
        return crossfadePlan(durationA, seconds: s.crossfadeSeconds, curve: s.crossfadeCurve)
    }

    guard let analysisA, let analysisB, analysisA.bpm > 0, analysisB.bpm > 0 else {
        return crossfadePlan(durationA, seconds: s.crossfadeEnabled ? s.crossfadeSeconds : 4, curve: s.crossfadeCurve)
    }

    let bpmA = analysisA.bpm
    let bpmB = analysisB.bpm
    // No track changes speed while it plays: the outgoing one keeps the speed
    // an earlier blend left it at, and the incoming one is matched to that.
    let outgoingRate = context.outgoingRate > 0 ? context.outgoingRate : 1
    let meetBpm = bpmA * outgoingRate

    let match = matchTempo(meetBpm, bpmB)
    let confident = analysisA.bpmConfidence >= 0.2 && analysisB.bpmConfidence >= 0.2
    let beatMatch = s.injektBeatMatch && confident && match.shift <= s.injektMaxTempoShift / 100

    let keyDistance = camelotDistance(analysisA.camelot, analysisB.camelot)
    let harmonicClash = s.injektHarmonic && keyDistance > 2
    let energyDelta = abs(analysisA.energy - analysisB.energy)

    // A calm blend gets long bars; a jarring pair gets a short, decisive one.
    var bars = s.injektBars
    if energyDelta > 0.35 { bars = min(bars, 4) }
    if harmonicClash { bars = min(bars, 4) }
    if !beatMatch { bars = min(bars, 4) }

    let barSeconds = 60 / bpmA * 4
    var duration = clamp(Double(bars) * barSeconds, MIN_TRANSITION, MAX_TRANSITION)
    duration = min(duration, durationA * 0.35)

    // Prefer the musical outro; never start before "now" and never overrun.
    let latestStart = durationA - duration
    var startAt = min(analysisA.outroStart, latestStart)
    startAt = max(startAt, context.currentTime + 1)

    // The blend has to begin on a bar of the outgoing track.
    if beatMatch {
        let aligned = snapDownToBar(analysisA, startAt)
        startAt = aligned >= context.currentTime + 0.5 ? aligned : aligned + barSeconds
    }

    startAt = clamp(startAt, 0, max(0, durationA - 0.5))
    // Shorten rather than overrun if alignment pushed the start point late.
    duration = min(duration, max(0.5, durationA - startAt))

    // Where the next track comes in: skip a long intro, land on a downbeat.
    var inStartOffset = 0.0
    if s.injektSkipIntro && analysisB.introEnd > 2.5 { inStartOffset = min(analysisB.introEnd, 45) }
    if beatMatch { inStartOffset = snapUpToBar(analysisB, inStartOffset) }
    let nextDuration = (next.duration ?? 0) > 0 ? Double(next.duration!) : analysisB.duration
    inStartOffset = clamp(inStartOffset, 0, max(0, nextDuration - 30))

    let type: TransitionType = harmonicClash ? .sweep : (beatMatch ? .blend : .crossfade)
    let incomingRate = beatMatch ? clamp(match.rate, 0.75, 1.35) : 1

    var details: [String] = []
    if beatMatch {
        let inDir = incomingRate >= 1 ? "up" : "down"
        details.append(
            "Beat-matched at \(fmt(meetBpm)) BPM — the next track \(inDir) \(fmt(abs(incomingRate - 1) * 100, 1))%, " +
                "and it stays at that tempo, so no track changes speed while it plays"
        )
    } else {
        details.append("\(fmt(meetBpm)) BPM into \(fmt(bpmB)) BPM, tempos too far apart to match")
    }
    details.append("keys \(analysisA.camelot) → \(analysisB.camelot)")
    if harmonicClash { details.append("keys clash, so the outgoing track is filtered out instead of blended") }
    if inStartOffset > 1 { details.append("intro skipped to \(fmt(inStartOffset, 1))s") }

    let label = beatMatch
        ? "InjeKt · \(fmt(bpmA))⇄\(fmt(bpmB)) @ \(fmt(meetBpm)) BPM · \(bars) bars"
        : "InjeKt · \(fmt(duration, 1))s \(harmonicClash ? "sweep" : "blend")"

    return TransitionPlan(
        type: type,
        // `duration` was measured in the outgoing track's timeline; during the
        // overlap it plays at `outgoingRate`, so the same music takes longer or less.
        duration: duration / outgoingRate,
        startAt: startAt,
        inStartOffset: inStartOffset,
        incomingRate: incomingRate,
        outgoingRate: outgoingRate,
        bassSwap: s.injektBassSwap && (type == .blend || type == .sweep),
        sweep: type == .sweep,
        curve: type == .sweep ? .sharp : .equalPower,
        label: label,
        reason: details.joined(separator: " · ")
    )
}

// ------------------------------------------------------------- auto queue --

/** How well [candidate] follows [from], 0..1. */
func affinity(_ from: TrackAnalysis, _ candidate: TrackAnalysis) -> Double {
    let tempoRatio = from.bpm > 0 && candidate.bpm > 0 ? candidate.bpm / from.bpm : 1
    let tempoDistance = min(abs(tempoRatio - 1), abs(tempoRatio - 2) / 2, abs(tempoRatio - 0.5) * 2)
    let tempoScore = exp(-tempoDistance * 10)
    let keyScore = 1 - min(1, camelotDistance(from.camelot, candidate.camelot) / 6)
    let energyScore = 1 - min(1, abs(from.energy - candidate.energy) * 1.6)
    let brightnessScore = 1 - min(1, abs(from.brightness - candidate.brightness) * 1.4)
    return tempoScore * 0.4 + keyScore * 0.25 + energyScore * 0.25 + brightnessScore * 0.1
}

/**
 * Re-rank auto-queue candidates by how well they mix out of the seed.
 * Unanalysed tracks get a middling score so they still get a turn. The best
 * few are lightly shuffled so the result does not become repetitive.
 */
func rankAutoQueue<R: RandomNumberGenerator>(
    seed: TrackAnalysis?,
    candidates: [(Song, TrackAnalysis?)],
    count: Int,
    random: inout R
) -> [Song] {
    if candidates.isEmpty { return [] }
    guard let seed else {
        return Array(candidates.map { $0.0 }.shuffled(using: &random).prefix(count))
    }
    var scored: [(Song, Double)] = []
    for (song, analysis) in candidates {
        let score = analysis.map { affinity(seed, $0) } ?? (0.45 + Double.random(in: 0..<1, using: &random) * 0.1)
        scored.append((song, score))
    }
    let ranked = scored.enumerated().sorted { lhs, rhs in
        lhs.element.1 != rhs.element.1 ? lhs.element.1 > rhs.element.1 : lhs.offset < rhs.offset
    }.map { $0.element.0 }
    return Array(Array(ranked.prefix(max(count, count * 3))).shuffled(using: &random).prefix(count))
}

func rankAutoQueue(seed: TrackAnalysis?, candidates: [(Song, TrackAnalysis?)], count: Int) -> [Song] {
    var generator = SystemRandomNumberGenerator()
    return rankAutoQueue(seed: seed, candidates: candidates, count: count, random: &generator)
}
