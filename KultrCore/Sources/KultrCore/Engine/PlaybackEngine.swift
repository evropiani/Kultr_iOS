import Foundation

enum RepeatMode: String, Codable, Hashable {
    case off, all, one
}

/** What the outside world sees. */
enum EngineStatus: Hashable {
    case idle, buffering, ready, ended
}

enum TrackChangeReason: Hashable {
    /** Something asked for this track: a new queue, a skip, a tap in the queue. */
    case user
    /** The previous track finished (or failed) and playback moved on. */
    case auto
    /** An overlapping transition (crossfade, InjeKt) brought this track in. */
    case transition
}

/** Everything the engine needs from the platform. */
@MainActor
protocol EngineHost: AnyObject {
    /** Monotonic clock, in milliseconds. */
    func now() -> Int64

    func settings() -> Settings

    /** Plan the hand-over from [current] to [next]. May analyse both tracks. */
    func plan(current: Song, next: Song, context: PlanContext) async throws -> TransitionPlan

    /** The queue ran out; return tracks to keep going with (or nothing). */
    func extendQueue(seed: Song, recent: [Song]) async throws -> [Song]

    /** Anything visible changed: queue, index, status, plan. */
    func onStateChanged()

    func onTrackStarted(_ item: QueueItem, reason: TrackChangeReason)

    func onError(_ message: String)
}

private func ms(_ seconds: Double) -> Int64 {
    guard seconds.isFinite else { return 0 }
    return Int64((seconds * 1000).rounded())
}

/**
 * Kultr's two-deck playback engine.
 *
 * Whenever crossfade or InjeKt is active, the next track is loaded on the idle
 * deck and both play at once for the length of the transition, each through
 * its own gain, low-shelf and high-pass, so basslines can be swapped and the
 * outgoing track swept out the way a DJ would. Gapless hand-overs are left to
 * the deck itself, which can join two files seamlessly.
 *
 * Single-threaded: every call, including [tick], happens on the main actor.
 * The platform calls [tick] on a timer — see [tickIntervalMs].
 */
@MainActor
final class PlaybackEngine: DeckListener {
    /**
     * How long before a hand-over the next track's audio is loaded. The
     * hand-over itself is planned as soon as the current track starts.
     */
    static let primeLeadMs: Int64 = 30_000
    static let incomingStartTimeoutMs: Int64 = 5_000
    static let bassCutDb = -26.0
    static let sweepFromHz = 20.0
    static let sweepToHz = 2400.0
    private static let maxErrorStreak = 4

    /** How long to wait before skipping a track that failed. */
    var errorSkipDelayMs: Int64 = 1_500

    private let decks: [Deck]
    private unowned let host: EngineHost
    private var activeSlot = 0
    private var active: Deck { decks[activeSlot] }
    private var idle: Deck { decks[1 - activeSlot] }

    /** Fade level (0..1) per deck, before ReplayGain. */
    private var fades: [Float] = [1, 0]

    private(set) var queue: [QueueItem] = []
    private var unshuffled: [QueueItem]?

    /** Index of the current item in [queue], or -1 when the queue is empty. */
    private(set) var index = -1
    private(set) var playWhenReady = false
    private(set) var repeatMode: RepeatMode = .off
    private(set) var shuffle = false

    /** True once the last item finished and nothing followed. */
    private(set) var ended = false

    /** Nothing is loaded (fresh start, or after [stop]). */
    private(set) var stopped = true
    private(set) var lastError: String?

    /** Pause when the current track ends instead of moving on (sleep timer). */
    var pauseAtEndOfTrack = false {
        didSet { if pauseAtEndOfTrack { clearPending() } }
    }

    private var stoppedPositionMs: Int64 = 0
    private var nextUid: Int64 = 1

    // ---------------------------------------------------------- transitions --

    private final class Pending {
        let item: QueueItem
        let plan: TransitionPlan
        /** Whether the next track's audio has been loaded for it yet (see [primeLeadMs]). */
        var primed = false
        init(item: QueueItem, plan: TransitionPlan) {
            self.item = item
            self.plan = plan
        }
    }

    private final class Crossing {
        let plan: TransitionPlan
        let from: Deck
        let to: Deck
        let requestedAt: Int64
        let durationMs: Int64
        let fromLevel: Float
        /** Engine clock when the incoming deck actually started; -1 while waiting. */
        var startedAt: Int64 = -1

        init(plan: TransitionPlan, from: Deck, to: Deck, requestedAt: Int64, durationMs: Int64, fromLevel: Float) {
            self.plan = plan
            self.from = from
            self.to = to
            self.requestedAt = requestedAt
            self.durationMs = durationMs
            self.fromLevel = fromLevel
        }
    }

    private struct Ramp {
        let deck: Deck
        let from: Double
        let to: Double
        let start: Int64
        let duration: Int64
    }

    /** Drift of the outgoing deck toward the meeting tempo, in its own timeline. */
    private struct Approach {
        let deck: Deck
        let rate: Double
        let fromMs: Int64
        let toMs: Int64
    }

    private var pending: Pending?
    private var preparedFor: Int64?
    private var planTask: Task<Void, Never>?
    private var crossing: Crossing?
    private var tempoRelease: Ramp?
    private var approach: Approach?
    private var errorStreak = 0
    private var extendTask: Task<Void, Never>?

    /** The plan for the track playing now, with the uid of the track it leads out of. */
    private(set) var lastPlan: (uid: Int64, plan: TransitionPlan)?

    /** The transition that is audible right now, if any. */
    var activeTransition: TransitionPlan? { crossing?.plan }

    /** The plan that will take the current track out, if one is ready. */
    var currentPlan: TransitionPlan? {
        guard let lastPlan, lastPlan.uid == currentItem?.uid else { return nil }
        return lastPlan.plan
    }

    /**
     * A clock that only runs while playback is wanted. Fades and ramps are
     * timed against it, so pausing halfway through a crossfade pauses the
     * crossfade too.
     */
    private var clock: Int64 = 0
    private var lastTickAt: Int64 = -1

    init(deckA: Deck, deckB: Deck, host: EngineHost) {
        decks = [deckA, deckB]
        self.host = host
        deckA.setListener(self)
        deckB.setListener(self)
    }

    // ------------------------------------------------------------ accessors --

    var currentItem: QueueItem? {
        index >= 0 && index < queue.count ? queue[index] : nil
    }

    var status: EngineStatus {
        if queue.isEmpty || stopped { return .idle }
        if ended { return .ended }
        switch active.status {
        case .ready, .ended, .error: return .ready
        default: return .buffering
        }
    }

    var positionMs: Int64 {
        if stopped { return stoppedPositionMs }
        if ended { return max(0, durationMs) }
        return max(0, active.positionMs)
    }

    var bufferedPositionMs: Int64 {
        stopped ? stoppedPositionMs : max(active.bufferedPositionMs, positionMs)
    }

    /** Duration of the current item, from the deck when known, else from the server. */
    var durationMs: Int64 {
        let fromDeck: Int64 = !stopped && active.item?.uid == currentItem?.uid ? active.durationMs : -1
        if fromDeck > 0 { return fromDeck }
        return Int64(currentItem?.song.duration ?? 0) * 1000
    }

    var isTransitioning: Bool { crossing != nil }

    func newItems(_ songs: [Song]) -> [QueueItem] {
        songs.map { song in
            defer { nextUid += 1 }
            return QueueItem(uid: nextUid, song: song)
        }
    }

    // ------------------------------------------------------------- transport --

    /** Replace the queue and load [startIndex] at [startPositionMs]. */
    func setQueue(_ items: [QueueItem], startIndex: Int, startPositionMs: Int64) {
        cancelTransition()
        clearPending()
        lastError = nil
        errorStreak = 0
        if items.isEmpty {
            queue = []
            unshuffled = nil
            index = -1
            unload()
            host.onStateChanged()
            return
        }
        var list = items
        var start = min(max(startIndex, 0), items.count - 1)
        unshuffled = nil
        if shuffle {
            unshuffled = items
            let shuffled = shuffledWithCurrentFirst(items, start)
            list = shuffled.items
            start = shuffled.index
        }
        queue = list
        index = start
        ended = false
        loadCurrent(max(0, startPositionMs))
        if playWhenReady { active.play() }
        host.onTrackStarted(queue[index], reason: .user)
        host.onStateChanged()
    }

    func setPlayWhenReady(_ value: Bool) {
        if playWhenReady == value { return }
        playWhenReady = value
        if value {
            if queue.isEmpty {
                host.onStateChanged()
                return
            }
            if stopped { loadCurrent(stoppedPositionMs) }
            active.play()
            if let crossing, crossing.from.item != nil { crossing.from.play() }
        } else {
            active.pause()
            crossing?.from.pause()
        }
        host.onStateChanged()
    }

    /** Make sure something is loaded, after [stop] or on a fresh start. */
    func prepare() {
        if queue.isEmpty || !stopped { return }
        loadCurrent(stoppedPositionMs)
        if playWhenReady { active.play() }
        host.onStateChanged()
    }

    func stop() {
        stoppedPositionMs = positionMs
        cancelTransition()
        clearPending()
        unload()
        host.onStateChanged()
    }

    /** Seek to [positionMs] in the item at [targetIndex]. */
    func seekTo(_ targetIndex: Int, positionMs: Int64, manual: Bool = true) {
        if queue.isEmpty { return }
        let target = min(max(targetIndex, 0), queue.count - 1)
        let position = max(0, positionMs)
        if target == index && !ended {
            cancelTransition()
            clearPending()
            if stopped {
                stoppedPositionMs = position
            } else {
                active.seekTo(position)
            }
            host.onStateChanged()
            return
        }
        skipTo(target, position, manual: manual)
    }

    func setRepeat(_ mode: RepeatMode) {
        if repeatMode == mode { return }
        repeatMode = mode
        clearPending()
        host.onStateChanged()
    }

    func setShuffle(_ enabled: Bool) {
        if shuffle == enabled { return }
        shuffle = enabled
        if !queue.isEmpty {
            if enabled {
                unshuffled = queue
                let shuffled = shuffledWithCurrentFirst(queue, index)
                queue = shuffled.items
                index = shuffled.index
            } else if let restored = unshuffled {
                let current = currentItem
                // Anything added while shuffled that the original order does
                // not know about goes to the end rather than disappearing.
                let known = Set(restored.map { $0.uid })
                let alive = Set(queue.map { $0.uid })
                let merged = restored.filter { alive.contains($0.uid) } + queue.filter { !known.contains($0.uid) }
                queue = merged
                if let current, let at = merged.firstIndex(where: { $0.uid == current.uid }) {
                    index = at
                } else {
                    index = 0
                }
            }
        }
        if !enabled { unshuffled = nil }
        clearPending()
        host.onStateChanged()
    }

    // ------------------------------------------------------------ queue edits --

    func addItems(at: Int, _ items: [QueueItem]) {
        if items.isEmpty { return }
        if queue.isEmpty {
            setQueue(items, startIndex: 0, startPositionMs: 0)
            return
        }
        let position = min(max(at, 0), queue.count)
        queue.insert(contentsOf: items, at: position)
        if position <= index { index += items.count }
        if var original = unshuffled {
            // "Play next" while shuffled should also be next once unshuffled.
            let anchor = position == index + 1 ? currentItem?.uid : nil
            let anchorAt = anchor.flatMap { uid in original.firstIndex(where: { $0.uid == uid }) } ?? -1
            if anchorAt >= 0 {
                original.insert(contentsOf: items, at: anchorAt + 1)
            } else {
                original.append(contentsOf: items)
            }
            unshuffled = original
        }
        revalidatePending()
        host.onStateChanged()
    }

    /** Remove [from] until [to] (exclusive). Removing the current item moves on. */
    func removeRange(_ from: Int, _ to: Int) {
        if queue.isEmpty { return }
        let start = min(max(from, 0), queue.count)
        let end = min(max(to, start), queue.count)
        if start == end { return }
        let removed = Set(queue[start..<end].map { $0.uid })
        var list = queue
        list.removeSubrange(start..<end)
        unshuffled = unshuffled?.filter { !removed.contains($0.uid) }
        let currentRemoved = index >= start && index < end
        queue = list
        if list.isEmpty {
            cancelTransition()
            clearPending()
            index = -1
            unload()
            host.onStateChanged()
            return
        }
        if currentRemoved {
            cancelTransition()
            clearPending()
            index = min(start, list.count - 1)
            if start >= list.count {
                // Removed the tail including the current item: nothing follows.
                ended = true
                active.pause()
            } else {
                ended = false
                if !stopped { loadCurrent(0) }
                if playWhenReady && !stopped { active.play() }
                host.onTrackStarted(queue[index], reason: .user)
            }
        } else if index >= end {
            index -= end - start
        }
        revalidatePending()
        host.onStateChanged()
    }

    /** Move [from]..[to] (exclusive) so it starts at [newIndex]. */
    func moveRange(_ from: Int, _ to: Int, newIndex: Int) {
        if queue.isEmpty { return }
        let start = min(max(from, 0), queue.count)
        let end = min(max(to, start), queue.count)
        if start == end { return }
        let current = currentItem
        var list = queue
        let moving = Array(list[start..<end])
        list.removeSubrange(start..<end)
        list.insert(contentsOf: moving, at: min(max(newIndex, 0), list.count))
        queue = list
        if let current, let at = list.firstIndex(where: { $0.uid == current.uid }) { index = at }
        revalidatePending()
        host.onStateChanged()
    }

    // --------------------------------------------------------------- settings --

    /** Re-read gains and invalidate plans after a settings change. */
    func onSettingsChanged(plansAffected: Bool) {
        applyLevel(active)
        if crossing == nil { applyLevel(idle) }
        if plansAffected { clearPending() }
    }

    func release() {
        planTask?.cancel()
        extendTask?.cancel()
        for deck in decks {
            deck.setListener(nil)
            deck.stop()
        }
    }

    // ------------------------------------------------------------------ tick --

    /** How often the platform should call [tick] right now. 0 means "no need". */
    func tickIntervalMs() -> Int64 {
        if crossing != nil || tempoRelease != nil || approach != nil { return 16 }
        if !playWhenReady || stopped || queue.isEmpty { return 0 }
        if let p = pending, p.plan.type != .gapless, p.plan.type != .cut {
            let untilStart = ms(p.plan.startAt) - active.positionMs
            if untilStart < ms(p.plan.outgoingRamp) + 1500 { return 16 }
        }
        return 250
    }

    func tick() {
        let now = host.now()
        if lastTickAt >= 0 && playWhenReady { clock += min(1000, max(0, now - lastTickAt)) }
        lastTickAt = now

        runTransition()
        runTempoRelease()

        if stopped || queue.isEmpty || !playWhenReady || crossing != nil { return }
        let deck = active
        guard let item = currentItem else { return }
        if deck.item?.uid != item.uid || deck.status != .ready { return }

        let position = deck.positionMs
        runApproach(deck, position)

        let duration = durationMs
        if duration <= 0 { return }
        if let p = pending {
            if !p.primed {
                if dueMs(p, duration) - position > Self.primeLeadMs { return }
                prime(p)
            }
            if p.plan.type == .gapless || p.plan.type == .cut { return }
            let startMs = min(ms(p.plan.startAt), duration - 50)
            let rampMs = ms(p.plan.outgoingRamp)
            if approach == nil && rampMs > 0 && abs(p.plan.outgoingRate - 1) > 0.001 &&
                position >= startMs - rampMs && position < startMs {
                approach = Approach(deck: deck, rate: p.plan.outgoingRate, fromMs: position, toMs: startMs)
            }
            if position >= startMs { executeTransition(p) }
        } else if preparedFor != item.uid && !pauseAtEndOfTrack {
            // Plan as soon as the track plays: the planner then has the whole
            // track to choose a mix-out point from, and the plan shows at once.
            prepareNext()
        }
    }

    /** Where in the current track the hand-over in [p] happens. */
    private func dueMs(_ p: Pending, _ duration: Int64) -> Int64 {
        switch p.plan.type {
        case .gapless, .cut: return duration
        default: return min(ms(p.plan.startAt), duration - 50)
        }
    }

    private func runApproach(_ deck: Deck, _ position: Int64) {
        guard let a = approach else { return }
        if a.deck !== deck {
            approach = nil
            return
        }
        let span = a.toMs - a.fromMs
        let t = span > 0 ? Double(position - a.fromMs) / Double(span) : 1
        if t >= 1 {
            deck.setRate(Float(a.rate))
            approach = nil
        } else if t >= 0 {
            let eased = t * t * (3 - 2 * t)
            deck.setRate(Float(1 + (a.rate - 1) * eased))
        }
    }

    private func runTempoRelease() {
        guard let r = tempoRelease else { return }
        let t = Double(clock - r.start) / Double(max(1, r.duration))
        if t >= 1 {
            r.deck.setRate(Float(r.to))
            tempoRelease = nil
        } else if t >= 0 {
            let eased = t * t * (3 - 2 * t)
            r.deck.setRate(Float(r.from + (r.to - r.from) * eased))
        }
    }

    private func runTransition() {
        guard let tr = crossing else { return }
        if tr.startedAt < 0 {
            // Wait for the incoming deck to actually make sound before the fade
            // clock starts, so a slow start never fades in silence.
            if !tr.to.isPlaying && clock - tr.requestedAt <= Self.incomingStartTimeoutMs { return }
            tr.startedAt = clock
        }
        let plan = tr.plan
        let t = tr.durationMs > 0 ? Double(clock - tr.startedAt) / Double(tr.durationMs) : 1
        if t >= 1 {
            finishTransition(tr)
            return
        }
        let fromFade = Double(tr.fromLevel) * curveValue(plan.curve, t, rising: false)
        let toFade = curveValue(plan.curve, t, rising: true)
        setFade(tr.from, Float(fromFade))
        setFade(tr.to, Float(toFade))
        if plan.bassSwap {
            // Drop the outgoing bass early, bring the incoming bass in late, so
            // the two kick drums never fight.
            tr.from.setBassDb(Float(Self.bassCutDb * min(1, t / 0.55)))
            tr.to.setBassDb(Float(Self.bassCutDb * (1 - max(0, (t - 0.35) / 0.65))))
        }
        if plan.sweep {
            tr.from.setSweepHz(Float(Self.sweepFromHz * pow(Self.sweepToHz / Self.sweepFromHz, t)))
        }
    }

    private func finishTransition(_ tr: Crossing) {
        crossing = nil
        tr.from.stop()
        resetDeck(tr.from)
        fades[slotOf(tr.from)] = 0
        setFade(tr.to, 1)
        tr.to.setBassDb(0)
        tr.to.setSweepHz(Float(Self.sweepFromHz))
        let plan = tr.plan
        if plan.tempoRelease > 0 && abs(plan.incomingRate - 1) > 0.001 {
            tempoRelease = Ramp(deck: tr.to, from: plan.incomingRate, to: 1, start: clock, duration: ms(plan.tempoRelease))
        }
        host.onStateChanged()
    }

    // --------------------------------------------------------------- planning --

    private func nextIndexAfter(_ current: Int) -> Int? {
        if queue.isEmpty { return nil }
        if repeatMode == .one { return current }
        if current + 1 < queue.count { return current + 1 }
        if repeatMode == .all { return 0 }
        return nil
    }

    private func peekNext() -> QueueItem? {
        nextIndexAfter(index).map { queue[$0] }
    }

    private func prepareNext() {
        guard let current = currentItem else { return }
        preparedFor = current.uid
        planTask?.cancel()
        planTask = Task { [weak self] in
            guard let self else { return }
            var next = self.peekNext()
            if next == nil && self.host.settings().injektAutoQueue {
                if await self.extendQueueNow(current) { next = self.peekNext() }
            }
            guard !Task.isCancelled, let next, self.currentItem?.uid == current.uid else { return }
            let context = PlanContext(
                durationA: Double(self.durationMs) / 1000,
                currentTime: Double(self.active.positionMs) / 1000
            )
            var plan: TransitionPlan
            do {
                plan = try await self.host.plan(current: current.song, next: next.song, context: context)
            } catch {
                if Task.isCancelled { return }
                plan = self.fallbackPlan(context.durationA)
            }
            guard !Task.isCancelled, self.currentItem?.uid == current.uid else { return }
            if self.peekNext()?.uid != next.uid {
                // The queue changed while this was being planned: plan again.
                self.preparedFor = nil
                return
            }
            self.setPending(next, plan)
        }
    }

    private func fallbackPlan(_ durationA: Double) -> TransitionPlan {
        let s = host.settings()
        if s.crossfadeEnabled && s.crossfadeSeconds > 0 { return crossfadePlan(durationA, seconds: s.crossfadeSeconds, curve: s.crossfadeCurve) }
        if s.gapless { return gaplessPlan(durationA) }
        return hardCutPlan(durationA)
    }

    private func extendQueueNow(_ seed: QueueItem) async -> Bool {
        let recent = queue.suffix(60).map { $0.song }
        let songs: [Song]
        do {
            songs = try await host.extendQueue(seed: seed.song, recent: Array(recent))
        } catch {
            songs = []
        }
        if Task.isCancelled || songs.isEmpty || queue.isEmpty { return false }
        let items = newItems(songs)
        queue += items
        if unshuffled != nil { unshuffled! += items }
        host.onStateChanged()
        return true
    }

    private func setPending(_ item: QueueItem, _ plan: TransitionPlan) {
        let p = Pending(item: item, plan: plan)
        pending = p
        if let current = currentItem { lastPlan = (current.uid, plan) }
        // Load the next track now only if the hand-over is close; otherwise
        // tick() does it nearer the time, so no stream is held open for minutes.
        let duration = durationMs
        if duration <= 0 || dueMs(p, duration) - active.positionMs <= Self.primeLeadMs { prime(p) }
        host.onStateChanged()
    }

    private func prime(_ p: Pending) {
        p.primed = true
        switch p.plan.type {
        case .gapless: active.setNext(p.item)
        case .cut: primeIdle(p.item, 0)
        default: primeIdle(p.item, ms(p.plan.inStartOffset))
        }
    }

    private func primeIdle(_ item: QueueItem, _ startMs: Int64) {
        if crossing != nil { return }
        let deck = idle
        resetDeck(deck)
        setFade(deck, 0)
        deck.load(item, startMs: startMs)
    }

    /** Forget the planned hand-over; it is rebuilt when needed. */
    private func clearPending() {
        planTask?.cancel()
        planTask = nil
        let hadPending = pending != nil
        pending = nil
        preparedFor = nil
        if let a = approach {
            a.deck.setRate(1)
            approach = nil
        }
        if !stopped { active.setNext(nil) }
        if crossing == nil && idle.item != nil { idle.stop() }
        if hadPending { lastPlan = nil }
    }

    /** After a queue edit: keep the plan only if it still leads to the right track. */
    private func revalidatePending() {
        if let p = pending, peekNext()?.uid != p.item.uid {
            clearPending()
        } else if pending == nil && preparedFor != nil {
            preparedFor = nil
        }
    }

    // ------------------------------------------------------------ hand-overs --

    private func executeTransition(_ p: Pending) {
        let from = active
        let to = idle
        let plan = p.plan
        guard let nextIndex = nextIndexAfter(index) else { return }
        pending = nil
        preparedFor = nil
        approach = nil

        if to.item?.uid != p.item.uid {
            resetDeck(to)
            to.load(p.item, startMs: ms(plan.inStartOffset))
        }
        if abs(plan.incomingRate - 1) > 0.001 { to.setRate(Float(plan.incomingRate)) }
        if abs(plan.outgoingRate - 1) > 0.001 { from.setRate(Float(plan.outgoingRate)) }
        if plan.bassSwap { to.setBassDb(Float(Self.bassCutDb)) }
        setFade(to, 0)
        to.play()

        activeSlot = slotOf(to)
        index = nextIndex
        ended = false
        crossing = Crossing(
            plan: plan,
            from: from,
            to: to,
            requestedAt: clock,
            durationMs: max(50, ms(plan.duration)),
            fromLevel: fades[slotOf(from)]
        )
        host.onTrackStarted(p.item, reason: .transition)
        host.onStateChanged()
    }

    /** Jump to another item, with a short crossfade if that is switched on. */
    private func skipTo(_ target: Int, _ positionMs: Int64, manual: Bool) {
        cancelTransition()
        clearPending()
        lastError = nil
        let item = queue[target]
        let s = host.settings()
        let fadeMs: Int64
        if manual && s.crossfadeOnSkip && s.crossfadeEnabled && playWhenReady && !stopped &&
            active.isPlaying && !item.song.isRadio && active.item?.song.isRadio != true {
            fadeMs = ms(min(s.crossfadeSeconds, 2.0))
        } else {
            fadeMs = 0
        }
        index = target
        ended = false
        if fadeMs > 50 {
            let from = active
            let to = idle
            resetDeck(to)
            setFade(to, 0)
            to.load(item, startMs: positionMs)
            to.play()
            activeSlot = slotOf(to)
            var plan = crossfadePlan(Double(fadeMs) / 1000 / 0.4, seconds: Double(fadeMs) / 1000, curve: .equalPower)
            plan.label = "Skip"
            plan.reason = "A short fade instead of a hard cut."
            crossing = Crossing(
                plan: plan,
                from: from,
                to: to,
                requestedAt: clock,
                durationMs: fadeMs,
                fromLevel: fades[slotOf(from)]
            )
        } else {
            loadCurrent(positionMs)
            if playWhenReady { active.play() }
        }
        host.onTrackStarted(item, reason: manual ? .user : .auto)
        host.onStateChanged()
    }

    /** The current deck finished and there was no overlapping transition. */
    private func onActiveEnded() {
        let p = pending
        if pauseAtEndOfTrack {
            pauseAtEndOfTrack = false
            let next = nextIndexAfter(index)
            clearPending()
            playWhenReady = false
            if let next {
                index = next
                loadCurrent(0)
                host.onTrackStarted(queue[index], reason: .auto)
            } else {
                ended = true
            }
            host.onStateChanged()
            return
        }
        if let p, p.plan.type == .cut, idle.item?.uid == p.item.uid, let nextIndex = nextIndexAfter(index) {
            let from = active
            let to = idle
            pending = nil
            preparedFor = nil
            activeSlot = slotOf(to)
            index = nextIndex
            setFade(to, 1)
            from.stop()
            fades[slotOf(from)] = 0
            if playWhenReady { to.play() }
            host.onTrackStarted(p.item, reason: .auto)
            host.onStateChanged()
            return
        }
        advanceAfterEnd()
    }

    private func advanceAfterEnd() {
        clearPending()
        if let next = nextIndexAfter(index) {
            skipTo(next, 0, manual: false)
            return
        }
        if let current = currentItem, host.settings().injektAutoQueue {
            extendTask?.cancel()
            extendTask = Task { [weak self] in
                guard let self else { return }
                if await self.extendQueueNow(current), self.currentItem?.uid == current.uid {
                    if let next = self.nextIndexAfter(self.index) { self.skipTo(next, 0, manual: false) }
                } else {
                    self.markEnded()
                }
            }
            return
        }
        markEnded()
    }

    private func markEnded() {
        ended = true
        host.onStateChanged()
    }

    // ---------------------------------------------------------- deck events --

    func onStatusChanged(_ deck: Deck) {
        if deck === active {
            if deck.status == .ready { errorStreak = 0 }
            if deck.status == .ended && crossing == nil && !stopped && !ended && deck.item?.uid == currentItem?.uid {
                onActiveEnded()
                return
            }
        } else if deck.status == .ended {
            // The outgoing deck of a transition ran out before its fade did.
            if let crossing, crossing.from === deck { deck.pause() }
        }
        host.onStateChanged()
    }

    func onError(_ deck: Deck, message: String) {
        if deck !== active {
            // A primed or outgoing deck failed; the hand-over falls back to a
            // normal load when the time comes.
            if let tr = crossing, tr.from === deck {
                finishTransition(tr)
            } else {
                clearPending()
            }
            return
        }
        lastError = message
        host.onError(message)
        errorStreak += 1
        let next = nextIndexAfter(index)
        if let next, next != index, errorStreak < Self.maxErrorStreak {
            let failed = currentItem?.uid
            let delay = errorSkipDelayMs
            Task { [weak self] in
                if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000) }
                guard let self, self.currentItem?.uid == failed else { return }
                self.skipTo(next, 0, manual: false)
            }
        } else {
            playWhenReady = false
            active.pause()
        }
        host.onStateChanged()
    }

    func onAutoAdvanced(_ deck: Deck, item: QueueItem) {
        if deck !== active { return }
        let nextIndex = nextIndexAfter(index)
        pending = nil
        preparedFor = nil
        if let nextIndex, queue[nextIndex].uid == item.uid {
            index = nextIndex
        } else if let found = queue.firstIndex(where: { $0.uid == item.uid }) {
            index = found
        }
        host.onTrackStarted(item, reason: .auto)
        host.onStateChanged()
    }

    // --------------------------------------------------------------- helpers --

    private func slotOf(_ deck: Deck) -> Int {
        deck === decks[0] ? 0 : 1
    }

    private func setFade(_ deck: Deck, _ fade: Float) {
        fades[slotOf(deck)] = fade
        applyLevel(deck)
    }

    private func applyLevel(_ deck: Deck) {
        let base: Float = deck.item.map { replayGainFor($0.song, host.settings()) } ?? 1
        deck.setLevel(base * fades[slotOf(deck)])
    }

    private func resetDeck(_ deck: Deck) {
        deck.setRate(1)
        deck.setBassDb(0)
        deck.setSweepHz(Float(Self.sweepFromHz))
    }

    private func loadCurrent(_ positionMs: Int64) {
        guard let item = currentItem else { return }
        idle.stop()
        fades[1 - activeSlot] = 0
        resetDeck(active)
        active.load(item, startMs: positionMs)
        stopped = false
        ended = false
        setFade(active, 1)
    }

    private func unload() {
        for deck in decks { deck.stop() }
        stopped = true
        ended = false
        approach = nil
        tempoRelease = nil
    }

    /** Abandon an overlapping transition, keeping the incoming track at full level. */
    private func cancelTransition() {
        if let tr = crossing {
            crossing = nil
            tr.from.stop()
            resetDeck(tr.from)
            fades[slotOf(tr.from)] = 0
            setFade(tr.to, 1)
            tr.to.setBassDb(0)
            tr.to.setSweepHz(Float(Self.sweepFromHz))
        }
        if let r = tempoRelease {
            r.deck.setRate(1)
            tempoRelease = nil
        }
    }

    private func shuffledWithCurrentFirst(_ items: [QueueItem], _ current: Int) -> (items: [QueueItem], index: Int) {
        guard current >= 0 && current < items.count else { return (items.shuffled(), 0) }
        let head = items[current]
        var rest = items
        rest.remove(at: current)
        return ([head] + rest.shuffled(), 0)
    }
}
