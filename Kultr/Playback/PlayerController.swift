import AVFoundation
import Foundation
import MediaPlayer
import Observation
import UIKit

struct QueueEntry: Hashable, Identifiable {
    let index: Int
    let song: Song
    let key: String

    var id: String { key }
}

struct PlayerUiState: Equatable {
    var queue: [QueueEntry] = []
    var index = -1
    var current: Song?
    var isPlaying = false
    var playWhenReady = false
    var buffering = false
    var ended = false
    var shuffle = false
    var repeatMode: RepeatMode = .off
    var durationMs: Int64 = 0

    var hasMedia: Bool { current != nil }
    var upNext: [QueueEntry] { index < 0 ? queue : Array(queue.dropFirst(index + 1)) }
}

/** A sleep timer: stop at a moment, or at the end of the current track. */
struct SleepTimer: Equatable {
    let endsAt: Date?
    let endOfTrack: Bool
}

struct TransitionInfo: Equatable {
    /** The plan that will take the current track out, once it has been made. */
    var upcoming: TransitionPlan?
    /** The transition that is audible right now. */
    var active: TransitionPlan?
    /** Id of the song the upcoming plan leads out of. */
    var fromSongId: String?
}

private struct SavedSession: Codable {
    let profileId: String
    let songs: [Song]
    let index: Int
    let positionMs: Int64
}

/** The queue and position, kept across launches when "Resume where you left off" is on. */
private enum SessionStore {
    static var file: URL { LibraryRepository.directory.appendingPathComponent("session.json") }

    static func save(_ session: SavedSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? data.write(to: file, options: .atomic)
    }

    static func load() -> SavedSession? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(SavedSession.self, from: data)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: file)
    }
}

/** Counts how long a track has really been listened to, for scrobbling. */
@MainActor
private final class ListeningTracker {
    private unowned let graph: AppGraph
    private var song: Song?
    private var listenedMs: Int64 = 0
    private var scrobbled = false

    init(graph: AppGraph) {
        self.graph = graph
    }

    func start(_ song: Song) {
        self.song = song
        listenedMs = 0
        scrobbled = false
        graph.scrobbles.nowPlaying(song)
    }

    func advance(_ deltaMs: Int64, durationMs: Int64, positionMs: Int64) {
        guard let current = song, !scrobbled, !current.isRadio else { return }
        listenedMs += min(1_000, max(0, deltaMs))
        let length = durationMs > 0 ? durationMs : Int64(current.duration ?? 0) * 1000
        let threshold = min(240_000, max(20_000, length / 2))
        if listenedMs >= threshold {
            scrobbled = true
            graph.scrobbles.played(current, seconds: Int(listenedMs / 1000), completed: positionMs >= length - 5_000, source: "")
        }
    }
}

/**
 * Hosts Kultr's engine and is the interface's side of playback: published
 * state for the screens, the commands they need, the lock screen and
 * Control Center, audio-session handling, the sleep timer and resume.
 */
@MainActor
@Observable
final class PlayerController: EngineHost {
    private(set) var state = PlayerUiState()
    private(set) var transition = TransitionInfo()
    private(set) var sleepTimer: SleepTimer?

    @ObservationIgnored private unowned let graph: AppGraph
    @ObservationIgnored private let eq = EqState()
    @ObservationIgnored private var decks: [AVDeck] = []
    @ObservationIgnored private var engine: PlaybackEngine!
    @ObservationIgnored private var tracker: ListeningTracker!
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTickAt: Int64 = 0
    @ObservationIgnored private var lastSavedAt: Int64 = 0
    @ObservationIgnored private var resumeAfterInterruption = false
    @ObservationIgnored private var artworkKey: String?
    @ObservationIgnored private var artwork: MPMediaItemArtwork?
    @ObservationIgnored private let clockStart = ProcessInfo.processInfo.systemUptime

    init(graph: AppGraph) {
        self.graph = graph
    }

    /** Called once the rest of the graph exists. */
    func start() {
        let sources = DeckSources(graph: graph)
        decks = [AVDeck(name: "A", sources: sources, eq: eq), AVDeck(name: "B", sources: sources, eq: eq)]
        engine = PlaybackEngine(deckA: decks[0], deckB: decks[1], host: self)
        tracker = ListeningTracker(graph: graph)
        applyEq(graph.settings.current)
        StreamCache.shared.setLimit(megabytes: graph.settings.current.streamCacheMb)

        graph.settings.observe { [weak self] old, new in
            guard let self else { return }
            self.applyEq(new)
            self.engine.onSettingsChanged(plansAffected: Self.planSignature(old) != Self.planSignature(new))
            if old.streamCacheMb != new.streamCacheMb { StreamCache.shared.setLimit(megabytes: new.streamCacheMb) }
        }
        // A different server has a different library; its queue makes no sense here.
        graph.auth.observeActive { [weak self] _ in
            guard let self else { return }
            self.engine.setQueue([], startIndex: 0, startPositionMs: 0)
            SessionStore.clear()
        }
        configureAudioSession()
        configureRemoteCommands()
        restore()
    }

    private static func planSignature(_ s: Settings) -> [String] {
        [
            "\(s.crossfadeEnabled)", "\(s.crossfadeSeconds)", s.crossfadeCurve.rawValue, "\(s.gapless)", "\(s.injektEnabled)",
            "\(s.injektBeatMatch)", "\(s.injektBassSwap)", "\(s.injektHarmonic)", "\(s.injektMaxTempoShift)",
            "\(s.injektTempoRamp)", "\(s.injektTempoBlend)", "\(s.injektBars)", "\(s.injektSkipIntro)",
        ]
    }

    private func applyEq(_ s: Settings) {
        eq.update(enabled: s.eqEnabled, gains: s.eqBandGains, preamp: s.eqPreamp)
    }

    // --------------------------------------------------------- restore --

    private func restore() {
        guard graph.settings.current.resumeOnStart else { return }
        _ = loadSavedSession()
    }

    /** Put the last saved queue back, at the position it stopped. False if there is none for this server. */
    private func loadSavedSession() -> Bool {
        guard let saved = SessionStore.load(), saved.profileId == graph.auth.active?.id, !saved.songs.isEmpty else { return false }
        engine.setQueue(engine.newItems(saved.songs), startIndex: saved.index, startPositionMs: saved.positionMs)
        return true
    }

    private func saveSession() {
        guard let profile = graph.auth.active else { return }
        let queue = engine.queue
        if queue.isEmpty {
            SessionStore.clear()
            return
        }
        // Keep the saved queue a sensible size around the current track.
        let from = max(0, engine.index - 100)
        let songs = queue.dropFirst(from).prefix(500).map { $0.song }
        SessionStore.save(SavedSession(profileId: profile.id, songs: Array(songs), index: engine.index - from, positionMs: engine.positionMs))
    }

    // ---------------------------------------------------------- state --

    private func publish() {
        let queue = engine.queue.enumerated().map { QueueEntry(index: $0.offset, song: $0.element.song, key: "\($0.offset):\($0.element.uid)") }
        let current = engine.currentItem?.song
        let status = engine.status
        var next = PlayerUiState(
            queue: queue,
            index: engine.queue.isEmpty ? -1 : engine.index,
            current: current,
            isPlaying: engine.playWhenReady && status == .ready,
            playWhenReady: engine.playWhenReady,
            buffering: status == .buffering,
            ended: status == .ended,
            shuffle: engine.shuffle,
            repeatMode: engine.repeatMode,
            durationMs: engine.durationMs
        )
        if next.durationMs <= 0 { next.durationMs = Int64(current?.duration ?? 0) * 1000 }
        if next != state { state = next }
        let info = TransitionInfo(upcoming: engine.currentPlan, active: engine.activeTransition, fromSongId: current?.id)
        if info != transition { transition = info }
        updateNowPlaying()
    }

    /** Current position; read it on a timer, it is not part of [state]. */
    func positionMs() -> Int64 {
        engine?.positionMs ?? 0
    }

    // ---------------------------------------------------------- ticking --

    private func scheduleTick() {
        timer?.invalidate()
        timer = nil
        var interval = engine.tickIntervalMs()
        if interval == 0 && sleepTimer?.endsAt != nil && engine.playWhenReady { interval = 1_000 }
        if interval == 0 && engine.playWhenReady { interval = 1_000 }
        guard interval > 0 else { return }
        let next = Timer(timeInterval: Double(interval) / 1000, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onTick()
                self?.scheduleTick()
            }
        }
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    private func onTick() {
        let now = self.now()
        let delta = lastTickAt == 0 ? 0 : now - lastTickAt
        lastTickAt = now
        engine.tick()
        if engine.playWhenReady && engine.status == .ready {
            tracker.advance(delta, durationMs: engine.durationMs, positionMs: engine.positionMs)
        }
        if let ends = sleepTimer?.endsAt, Date() >= ends {
            sleepTimer = nil
            pause()
            graph.messages.show("Sleep timer finished. Good night.")
        }
        if engine.playWhenReady && now - lastSavedAt > 10_000 {
            lastSavedAt = now
            saveSession()
            updateNowPlaying()
        }
    }

    // ------------------------------------------------------ EngineHost --

    func now() -> Int64 {
        Int64((ProcessInfo.processInfo.systemUptime - clockStart) * 1000) + 1
    }

    func settings() -> Settings {
        graph.settings.current
    }

    func plan(current: Song, next: Song, context: PlanContext) async throws -> TransitionPlan {
        let s = graph.settings.current
        if !s.injektEnabled {
            return planTransition(current: current, next: next, context: context, settings: s, analysisA: nil, analysisB: nil)
        }
        let a = await withTimeout(25) { await self.graph.analysis.getOrAnalyse(current) }
        let b = await withTimeout(25) { await self.graph.analysis.getOrAnalyse(next) }
        // Analysis can take a while; plan against where playback is now.
        var fresh = context
        fresh.currentTime = Double(engine.positionMs) / 1000
        return planTransition(current: current, next: next, context: fresh, settings: s, analysisA: a ?? nil, analysisB: b ?? nil)
    }

    private func withTimeout<T: Sendable>(_ seconds: Double, _ body: @escaping @MainActor () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await body() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    func extendQueue(seed: Song, recent: [Song]) async throws -> [Song] {
        await AutoQueue(graph: graph).build(seed: seed, recent: recent)
    }

    func onStateChanged() {
        publish()
        if let timer = sleepTimer, timer.endOfTrack, !engine.pauseAtEndOfTrack { sleepTimer = nil }
        if !engine.playWhenReady { saveSession() }
        scheduleTick()
    }

    func onTrackStarted(_ item: QueueItem, reason: TrackChangeReason) {
        tracker.start(item.song)
        // This track and the next are analysed for the plan made now; look
        // one further, so skipping ahead lands on a transition that is ready too.
        for ahead in 1...2 where engine.index + ahead < engine.queue.count {
            graph.analysis.analyseAhead(engine.queue[engine.index + ahead].song)
        }
        saveSession()
    }

    func onError(_ message: String) {
        graph.messages.error(message)
    }

    // --------------------------------------------------------- commands --

    private func setPlaying(_ playing: Bool) {
        if playing {
            activateSession()
            engine.setPlayWhenReady(true)
        } else {
            resumeAfterInterruption = false
            engine.setPlayWhenReady(false)
        }
    }

    func play(_ songs: [Song], startIndex: Int = 0, shuffle: Bool = false) {
        guard !songs.isEmpty else { return }
        if engine.shuffle != shuffle { engine.setShuffle(shuffle) }
        engine.setQueue(engine.newItems(songs), startIndex: min(max(0, startIndex), songs.count - 1), startPositionMs: 0)
        engine.prepare()
        setPlaying(true)
    }

    func playNext(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        if engine.queue.isEmpty {
            play(songs)
        } else {
            engine.addItems(at: engine.index + 1, engine.newItems(songs))
        }
        graph.messages.show(songs.count == 1 ? "“\(songs[0].title)” plays next" : "\(songs.count) tracks play next")
    }

    func enqueue(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        if engine.queue.isEmpty {
            play(songs)
        } else {
            engine.addItems(at: engine.queue.count, engine.newItems(songs))
        }
        graph.messages.show(songs.count == 1 ? "Added “\(songs[0].title)” to the queue" : "Added \(songs.count) tracks to the queue")
    }

    func toggle() {
        if engine.queue.isEmpty {
            resume()
        } else if engine.status == .ended {
            engine.seekTo(0, positionMs: 0, manual: false)
            setPlaying(true)
        } else if engine.playWhenReady {
            pause()
        } else {
            engine.prepare()
            setPlaying(true)
        }
    }

    /**
     * Play. With nothing loaded (after the app was closed, from headphones or
     * Control Center), pick up the last queue where it stopped.
     */
    func resume() {
        if engine.queue.isEmpty && !loadSavedSession() { return }
        engine.prepare()
        setPlaying(true)
    }

    func pause() {
        setPlaying(false)
    }

    func next() {
        guard !engine.queue.isEmpty else { return }
        if engine.index + 1 < engine.queue.count {
            engine.seekTo(engine.index + 1, positionMs: 0)
        } else if engine.repeatMode == .all {
            engine.seekTo(0, positionMs: 0)
        }
    }

    func previous() {
        guard !engine.queue.isEmpty else { return }
        let hasPrevious = engine.index > 0 || engine.repeatMode == .all
        if engine.positionMs <= 3_000 && hasPrevious {
            engine.seekTo(engine.index > 0 ? engine.index - 1 : engine.queue.count - 1, positionMs: 0)
        } else {
            engine.seekTo(engine.index, positionMs: 0)
        }
    }

    func seekTo(_ positionMs: Int64) {
        engine.seekTo(engine.index, positionMs: positionMs)
    }

    func jumpTo(_ index: Int) {
        engine.seekTo(index, positionMs: 0)
        setPlaying(true)
    }

    func move(_ from: Int, _ to: Int) {
        engine.moveRange(from, from + 1, newIndex: to)
    }

    func remove(_ index: Int) {
        engine.removeRange(index, index + 1)
    }

    /** Drop everything after the current track. */
    func clearUpcoming() {
        let start = engine.index + 1
        if start < engine.queue.count { engine.removeRange(start, engine.queue.count) }
    }

    func setShuffle(_ enabled: Bool) {
        engine.setShuffle(enabled)
    }

    func cycleRepeat() {
        switch engine.repeatMode {
        case .off: engine.setRepeat(.all)
        case .all: engine.setRepeat(.one)
        case .one: engine.setRepeat(.off)
        }
    }

    func stop() {
        pause()
        engine.removeRange(0, engine.queue.count)
    }

    // ------------------------------------------------------ sleep timer --

    func setSleepTimer(minutes: Int) {
        engine.pauseAtEndOfTrack = false
        sleepTimer = SleepTimer(endsAt: Date().addingTimeInterval(Double(minutes) * 60), endOfTrack: false)
        scheduleTick()
    }

    func sleepAtEndOfTrack() {
        sleepTimer = SleepTimer(endsAt: nil, endOfTrack: true)
        engine.pauseAtEndOfTrack = true
    }

    func clearSleepTimer() {
        sleepTimer = nil
        engine.pauseAtEndOfTrack = false
    }

    // ---------------------------------------------------- audio session --

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, policy: .longFormAudio)
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            let info = note.userInfo
            MainActor.assumeIsolated { self?.handleInterruption(info) }
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] note in
            let info = note.userInfo
            MainActor.assumeIsolated { self?.handleRouteChange(info) }
        }
    }

    private func activateSession() {
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func handleInterruption(_ info: [AnyHashable: Any]?) {
        guard let raw = info?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }
        switch type {
        case .began:
            if engine.playWhenReady {
                engine.setPlayWhenReady(false)
                resumeAfterInterruption = true
            }
        case .ended:
            let options = (info?[AVAudioSessionInterruptionOptionKey] as? UInt).map { AVAudioSession.InterruptionOptions(rawValue: $0) } ?? []
            if resumeAfterInterruption && options.contains(.shouldResume) {
                resumeAfterInterruption = false
                activateSession()
                engine.setPlayWhenReady(true)
            }
        @unknown default:
            break
        }
    }

    /** Headphones unplugged (or a Bluetooth speaker gone): pause, like every music app. */
    private func handleRouteChange(_ info: [AnyHashable: Any]?) {
        guard let raw = info?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable
        else { return }
        if engine.playWhenReady { pause() }
    }

    // --------------------------------------------------- lock screen etc --

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.toggle() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let ms = Int64(event.positionTime * 1000)
            MainActor.assumeIsolated { self?.seekTo(ms) }
            return .success
        }
    }

    private func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard let song = state.current else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(engine.positionMs) / 1000,
            MPNowPlayingInfoPropertyPlaybackRate: state.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: song.isRadio,
        ]
        if let artist = song.artist { info[MPMediaItemPropertyArtist] = artist }
        if let album = song.album, !song.isRadio { info[MPMediaItemPropertyAlbumTitle] = album }
        if state.durationMs > 0 { info[MPMediaItemPropertyPlaybackDuration] = Double(state.durationMs) / 1000 }
        let key = song.artworkId
        if key != artworkKey {
            artworkKey = key
            artwork = nil
            if let url = graph.auth.client?.coverArtUrl(key, size: 600) {
                Task { [weak self] in
                    guard let image = await ImageLoader.shared.image(url, pixelSize: 600), let self, self.artworkKey == key else { return }
                    self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    self.updateNowPlaying()
                }
            }
        }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        center.nowPlayingInfo = info
        center.playbackState = state.isPlaying ? .playing : .paused
    }
}
