import Foundation

/** One entry in the play queue. [uid] tells apart two copies of the same song. */
struct QueueItem: Hashable {
    let uid: Int64
    let song: Song
}

enum DeckStatus: Hashable {
    case idle, buffering, ready, ended, error
}

/**
 * One of the two players the engine mixes between. On iOS this is an
 * AVQueuePlayer with Kultr's audio tap on its tracks; in tests, a fake.
 *
 * Every method is called on the main actor.
 */
@MainActor
protocol Deck: AnyObject {
    var name: String { get }

    /** What is loaded right now, or nil. */
    var item: QueueItem? { get }
    var status: DeckStatus { get }
    var positionMs: Int64 { get }

    /** Length of the loaded item, or a value <= 0 when not known yet. */
    var durationMs: Int64 { get }
    var bufferedPositionMs: Int64 { get }

    /** True when audio is actually coming out. */
    var isPlaying: Bool { get }

    /** Load [item] paused at [startMs]. Replaces anything loaded before. */
    func load(_ item: QueueItem, startMs: Int64)
    func play()
    func pause()
    func seekTo(_ positionMs: Int64)

    /** Unload everything and go idle. */
    func stop()

    /**
     * Queue [item] to follow the loaded one without a gap — the deck moves on
     * by itself and reports it through [DeckListener.onAutoAdvanced]. Nil
     * removes a previously queued follower.
     */
    func setNext(_ item: QueueItem?)

    /** Final linear gain, fade × ReplayGain; the deck smooths the change. */
    func setLevel(_ level: Float)
    func setRate(_ rate: Float)

    /** Low-shelf (≈180 Hz) gain in dB — 0 is flat. Used for the bass swap. */
    func setBassDb(_ db: Float)

    /** High-pass corner in Hz — 20 is effectively off. Used for the sweep. */
    func setSweepHz(_ hz: Float)

    func setListener(_ listener: DeckListener?)
}

@MainActor
protocol DeckListener: AnyObject {
    func onStatusChanged(_ deck: Deck)
    func onError(_ deck: Deck, message: String)

    /** The deck moved on to the item given to [Deck.setNext] by itself. */
    func onAutoAdvanced(_ deck: Deck, item: QueueItem)
}

/** Shape of a fade at `t` in 0..1, for a rising or falling fade. */
func curveValue(_ curve: CrossfadeCurve, _ t: Double, rising: Bool) -> Double {
    let x = min(1, max(0, t))
    switch curve {
    case .linear:
        return rising ? x : 1 - x
    case .smooth:
        let s = x * x * (3 - 2 * x)
        return rising ? s : 1 - s
    case .sharp:
        // Fast out, slow in — keeps a busy mix from turning to mud.
        return rising ? pow(x, 0.6) : 1 - pow(x, 1.8)
    case .equalPower:
        return rising ? sin(x * Double.pi / 2) : cos(x * Double.pi / 2)
    }
}

/** Linear gain for a song, honouring the ReplayGain settings. */
func replayGainFor(_ song: Song, _ settings: Settings) -> Float {
    let mode = settings.replayGainMode
    if mode == .off { return 1 }
    guard let rg = song.replayGain else { return 1 }
    let gainDb = mode == .album ? (rg.albumGain ?? rg.trackGain) : rg.trackGain
    guard let gainDb else { return 1 }
    let peak = (mode == .album ? (rg.albumPeak ?? rg.trackPeak) : rg.trackPeak) ?? 1.0
    var scale = pow(10.0, (gainDb + settings.replayGainPreamp) / 20)
    // Never push a track into clipping.
    if peak > 0 && scale * peak > 1 { scale = 1 / peak }
    return Float(min(4.0, max(0.05, scale)))
}
