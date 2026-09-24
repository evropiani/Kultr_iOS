import XCTest
@testable import KultrCore

/** A deck that plays silence against a fake clock. */
@MainActor
final class FakeDeck: Deck {
    let name: String
    private let clock: () -> Int64
    var item: QueueItem?
    var status: DeckStatus = .idle
    var durationMs: Int64 = -1
    private var base: Int64 = 0
    private var since: Int64?
    private var wantPlay = false
    private(set) var rate: Float = 1
    private(set) var level: Float = 0
    private(set) var bass: Float = 0
    private(set) var sweep: Float = 20
    private(set) var next: QueueItem?
    var failNextLoad = false
    private weak var listener: DeckListener?

    init(_ name: String, clock: @escaping () -> Int64) {
        self.name = name
        self.clock = clock
    }

    var positionMs: Int64 {
        base + (since.map { Int64(Double(clock() - $0) * Double(rate)) } ?? 0)
    }

    var bufferedPositionMs: Int64 { positionMs }
    var isPlaying: Bool { status == .ready && wantPlay }

    func load(_ item: QueueItem, startMs: Int64) {
        self.item = item
        base = startMs
        since = nil
        wantPlay = false
        next = nil
        durationMs = Int64(item.song.duration ?? 0) * 1000
        status = .buffering
    }

    func play() {
        wantPlay = true
        if status == .ready && since == nil { since = clock() }
    }

    func pause() {
        freeze()
        wantPlay = false
        since = nil
    }

    private func freeze() {
        base = positionMs
        since = since != nil ? clock() : nil
    }

    func seekTo(_ positionMs: Int64) {
        base = positionMs
        if since != nil { since = clock() }
        if status == .ended { status = .ready }
    }

    func stop() {
        item = nil
        next = nil
        since = nil
        wantPlay = false
        base = 0
        status = .idle
    }

    func setNext(_ item: QueueItem?) { next = item }
    func setLevel(_ level: Float) { self.level = level }

    func setRate(_ rate: Float) {
        freeze()
        self.rate = rate
    }

    func setBassDb(_ db: Float) { bass = db }
    func setSweepHz(_ hz: Float) { sweep = hz }
    func setListener(_ listener: DeckListener?) { self.listener = listener }

    /** Advance the simulation: finish loading, reach the end, move on gaplessly. */
    func update() {
        if status == .buffering {
            if failNextLoad {
                failNextLoad = false
                status = .error
                listener?.onError(self, message: "boom")
                return
            }
            status = .ready
            if wantPlay { since = clock() }
            listener?.onStatusChanged(self)
        }
        if status == .ready, since != nil, durationMs > 0, positionMs >= durationMs {
            if let following = next {
                let overflow = positionMs - durationMs
                item = following
                next = nil
                durationMs = Int64(following.song.duration ?? 0) * 1000
                base = overflow
                since = clock()
                listener?.onAutoAdvanced(self, item: following)
            } else {
                base = durationMs
                since = nil
                status = .ended
                listener?.onStatusChanged(self)
            }
        }
    }
}

@MainActor
final class PlaybackEngineTests: XCTestCase, EngineHost {
    private var clockMs: Int64 = 0
    private var a: FakeDeck!
    private var b: FakeDeck!
    private var settingsValue = Settings()
    private var started: [(String, TrackChangeReason)] = []
    private var errors: [String] = []
    private var extensionSongs: [Song] = []
    private var planOverride: ((Song, Song, PlanContext) -> TransitionPlan)?
    private var engine: PlaybackEngine!

    override func setUp() async throws {
        clockMs = 0
        settingsValue = Settings().with {
            $0.injektEnabled = false
            $0.crossfadeSeconds = 6
        }
        a = FakeDeck("A") { [unowned self] in self.clockMs }
        b = FakeDeck("B") { [unowned self] in self.clockMs }
        started = []
        errors = []
        extensionSongs = []
        planOverride = nil
        engine = PlaybackEngine(deckA: a, deckB: b, host: self)
        engine.errorSkipDelayMs = 0
    }

    override func tearDown() async throws {
        engine.release()
        engine = nil
    }

    // EngineHost
    func now() -> Int64 { clockMs }
    func settings() -> Settings { settingsValue }

    func plan(current: Song, next: Song, context: PlanContext) async throws -> TransitionPlan {
        if let planOverride { return planOverride(current, next, context) }
        return planTransition(current: current, next: next, context: context, settings: settingsValue, analysisA: nil, analysisB: nil)
    }

    func extendQueue(seed: Song, recent: [Song]) async throws -> [Song] {
        defer { extensionSongs = [] }
        return extensionSongs
    }

    func onStateChanged() {}

    func onTrackStarted(_ item: QueueItem, reason: TrackChangeReason) {
        started.append((item.song.id, reason))
    }

    func onError(_ message: String) {
        errors.append(message)
    }

    private func songs(_ ids: [String], seconds: Int = 60) -> [Song] {
        ids.map { Song(id: $0, title: $0, duration: seconds) }
    }

    private func advance(_ ms: Int64, step: Int64 = 10) async {
        var left = ms
        while left > 0 {
            let dt = min(step, left)
            clockMs += dt
            a.update()
            b.update()
            engine.tick()
            for _ in 0..<3 { await Task.yield() }
            left -= dt
        }
    }

    private func start(_ ids: [String], seconds: Int = 60) async {
        engine.setQueue(engine.newItems(songs(ids, seconds: seconds)), startIndex: 0, startPositionMs: 0)
        engine.setPlayWhenReady(true)
        await advance(20)
    }

    private var activeDeck: FakeDeck {
        a.isPlaying && a.item?.uid == engine.currentItem?.uid ? a : b
    }

    func testPlaysTheFirstTrack() async {
        await start(["1", "2"])
        XCTAssertEqual(engine.status, .ready)
        XCTAssertTrue(a.isPlaying)
        await advance(5_000)
        XCTAssertLessThan(abs(engine.positionMs - 5_000), 50)
        XCTAssertEqual(started.first?.0, "1")
        XCTAssertEqual(started.first?.1, .user)
    }

    func testCrossfadesIntoTheNextTrack() async {
        await start(["1", "2"])
        await advance(30_000)
        XCTAssertEqual(b.item?.song.id, "2")
        XCTAssertFalse(b.isPlaying)
        XCTAssertEqual(engine.currentPlan?.type, .crossfade)

        await advance(24_500)
        XCTAssertEqual(engine.index, 1)
        XCTAssertTrue(engine.isTransitioning)
        XCTAssertTrue(a.isPlaying && b.isPlaying)
        XCTAssertEqual(started.last?.0, "2")
        XCTAssertEqual(started.last?.1, .transition)

        await advance(2_500)
        XCTAssertTrue((0.3...0.95).contains(Double(a.level)), "outgoing \(a.level)")
        XCTAssertTrue((0.3...0.95).contains(Double(b.level)), "incoming \(b.level)")
        XCTAssertLessThan(abs(a.level * a.level + b.level * b.level - 1), 0.05)

        await advance(4_000)
        XCTAssertFalse(engine.isTransitioning)
        XCTAssertNil(a.item)
        XCTAssertEqual(b.level, 1)
        XCTAssertLessThan(abs(engine.positionMs - 7_000), 100, "position \(engine.positionMs)")
    }

    func testPlansWhenATrackStartsButLoadsTheNextOnlyNearTheMix() async {
        await start(["1", "2"], seconds: 300)
        await advance(1_000)
        // The plan is ready (and showing) within a second of the track starting...
        XCTAssertEqual(engine.currentPlan?.type, .crossfade)
        // ...but no stream is opened for a mix four and a half minutes away.
        XCTAssertNil(b.item)

        await advance(262_000, step: 100) // 263s: the fade starts at 294s, 31s away
        XCTAssertNil(b.item)
        await advance(2_000) // 265s: within 30s of it
        XCTAssertEqual(b.item?.song.id, "2")
        XCTAssertFalse(b.isPlaying)

        await advance(30_000, step: 50)
        XCTAssertEqual(engine.index, 1)
        XCTAssertTrue(engine.isTransitioning)
    }

    func testAQueueEditWhilePlanningPlansAgain() async {
        var planned: [String] = []
        planOverride = { [unowned self] current, next, context in
            planned.append(next.id)
            // Something is queued to play next while the first plan is being made.
            if planned.count == 1 { self.engine.addItems(at: self.engine.index + 1, self.engine.newItems(self.songs(["late"]))) }
            return planTransition(current: current, next: next, context: context, settings: self.settingsValue, analysisA: nil, analysisB: nil)
        }
        await start(["1", "2"])
        await advance(1_000)
        XCTAssertEqual(planned, ["2", "late"])
        await advance(54_000, step: 50)
        XCTAssertEqual(started.last?.0, "late")
        XCTAssertEqual(started.last?.1, .transition)
    }

    func testGaplessLetsTheDeckJoinTheTracks() async {
        settingsValue.crossfadeEnabled = false
        settingsValue.gapless = true
        await start(["1", "2", "3"])
        await advance(30_000)
        XCTAssertEqual(a.next?.song.id, "2")
        XCTAssertNil(b.item)
        await advance(30_100)
        XCTAssertEqual(engine.index, 1)
        XCTAssertEqual(started.last?.1, .auto)
        XCTAssertTrue(a.isPlaying)
    }

    func testHardCutStartsThePrimedDeckWhenTheTrackEnds() async {
        settingsValue.crossfadeEnabled = false
        settingsValue.gapless = false
        await start(["1", "2"])
        await advance(30_000)
        XCTAssertEqual(b.item?.song.id, "2")
        await advance(30_100)
        XCTAssertEqual(engine.index, 1)
        XCTAssertTrue(b.isPlaying)
        XCTAssertNil(a.item)
    }

    func testManualSkipFades() async {
        await start(["1", "2", "3"])
        await advance(10_000)
        engine.seekTo(2, positionMs: 0)
        XCTAssertEqual(engine.index, 2)
        XCTAssertTrue(engine.isTransitioning)
        await advance(2_200)
        XCTAssertFalse(engine.isTransitioning)
        XCTAssertEqual(activeDeck.item?.song.id, "3")
        XCTAssertEqual([a!, b!].filter { $0.item != nil }.count, 1)
    }

    func testSeekingWithinATrackClearsThePlan() async {
        await start(["1", "2"])
        await advance(30_000)
        XCTAssertNotNil(engine.currentPlan)
        engine.seekTo(0, positionMs: 5_000)
        XCTAssertNil(b.item)
        XCTAssertNil(engine.currentPlan)
        await advance(500)
        XCTAssertTrue((5_000...6_000).contains(engine.positionMs))
    }

    func testEndOfQueueEnds() async {
        settingsValue.injektAutoQueue = false
        await start(["1"], seconds: 20)
        await advance(21_000)
        XCTAssertEqual(engine.status, .ended)
        XCTAssertEqual(engine.index, 0)
    }

    func testAutoQueueKeepsTheMusicGoing() async {
        settingsValue.injektAutoQueue = true
        extensionSongs = songs(["x", "y"])
        await start(["1"])
        await advance(30_000)
        XCTAssertEqual(engine.queue.count, 3)
        await advance(31_000)
        XCTAssertEqual(engine.index, 1)
        XCTAssertEqual(engine.currentItem?.song.id, "x")
    }

    func testQueueEditsKeepTheCurrentTrack() async {
        await start(["1", "2", "3"])
        engine.seekTo(1, positionMs: 0)
        await advance(3_000)
        engine.addItems(at: 0, engine.newItems(songs(["0"])))
        XCTAssertEqual(engine.index, 2)
        XCTAssertEqual(engine.currentItem?.song.id, "2")
        engine.moveRange(2, 3, newIndex: 0)
        XCTAssertEqual(engine.index, 0)
        XCTAssertEqual(engine.queue.map { $0.song.id }, ["2", "0", "1", "3"])
    }

    func testShuffleKeepsTheCurrentTrackFirstAndUnshuffleRestores() async {
        await start(["1", "2", "3", "4", "5", "6"])
        engine.seekTo(2, positionMs: 0)
        await advance(3_000)
        engine.setShuffle(true)
        XCTAssertEqual(engine.index, 0)
        XCTAssertEqual(engine.currentItem?.song.id, "3")
        XCTAssertEqual(Set(engine.queue.map { $0.song.id }), ["1", "2", "3", "4", "5", "6"])
        engine.setShuffle(false)
        XCTAssertEqual(engine.queue.map { $0.song.id }, ["1", "2", "3", "4", "5", "6"])
        XCTAssertEqual(engine.index, 2)
    }

    func testPauseAtEndOfTrackStopsOnTheNextOne() async {
        await start(["1", "2"])
        engine.pauseAtEndOfTrack = true
        await advance(61_000)
        XCTAssertFalse(engine.playWhenReady)
        XCTAssertEqual(engine.index, 1)
        XCTAssertFalse(a.isPlaying || b.isPlaying)
    }

    func testInjektPlansDriveRatesAndTheBassSwap() async {
        settingsValue.injektEnabled = true
        planOverride = { _, _, _ in
            TransitionPlan(
                type: .blend, duration: 8, startAt: 48, inStartOffset: 4,
                incomingRate: 0.98, outgoingRate: 1.02, outgoingRamp: 6, tempoRelease: 4,
                bassSwap: true, sweep: false, curve: .equalPower, label: "InjeKt", reason: ""
            )
        }
        await start(["1", "2"])
        await advance(30_000)
        XCTAssertEqual(b.item?.song.id, "2")
        XCTAssertLessThan(abs(b.positionMs - 4_000), 10)
        await advance(15_000)
        XCTAssertTrue(a.rate > 1 && a.rate < 1.02, "approach rate \(a.rate)")
        await advance(3_100)
        XCTAssertTrue(engine.isTransitioning)
        XCTAssertEqual(a.rate, 1.02, accuracy: 0.001)
        XCTAssertEqual(b.rate, 0.98, accuracy: 0.001)
        await advance(4_000)
        XCTAssertLessThan(a.bass, -10)
        XCTAssertTrue(b.bass < 0 && b.bass > -26, "incoming bass \(b.bass)")
        await advance(4_200)
        XCTAssertFalse(engine.isTransitioning)
        XCTAssertEqual(b.bass, 0)
        await advance(4_100)
        XCTAssertEqual(b.rate, 1, accuracy: 0.001)
    }

    func testAFailedTrackIsSkipped() async {
        a.failNextLoad = true
        engine.setQueue(engine.newItems(songs(["bad", "good"])), startIndex: 0, startPositionMs: 0)
        engine.setPlayWhenReady(true)
        await advance(2_000)
        XCTAssertEqual(errors, ["boom"])
        XCTAssertEqual(engine.currentItem?.song.id, "good")
        XCTAssertTrue(activeDeck.isPlaying)
    }

    func testStopAndPrepareResumeWhereWeWere() async {
        await start(["1", "2"])
        await advance(12_000)
        engine.stop()
        XCTAssertEqual(engine.status, .idle)
        XCTAssertLessThan(abs(engine.positionMs - 12_000), 50)
        engine.prepare()
        await advance(20)
        XCTAssertLessThan(abs(engine.positionMs - 12_000), 100)
    }
}
