import AVFoundation
import Foundation

/** Where a queue item's audio comes from. */
enum DeckSource {
    /** Internet radio: the station URL, played as-is. */
    case radio(URL)
    /** An offline copy or a complete stream-cache file. */
    case file(URL, mimeType: String?)
    /** Streamed through the caching loader, with the plain URL to fall back on. */
    case stream(StreamingResource, direct: URL)
    /** Streamed straight by AVPlayer, no cache. */
    case direct(URL)
}

/**
 * Picks the source for a track: the offline copy when there is one, the
 * stream cache, else the (cached) Subsonic stream; the station URL for radio.
 */
@MainActor
final class DeckSources {
    private unowned let graph: AppGraph

    init(graph: AppGraph) {
        self.graph = graph
    }

    func source(for item: QueueItem, direct: Bool = false) -> DeckSource? {
        let song = item.song
        if let station = song.kultrStreamUrl {
            return URL(string: station).map { .radio($0) }
        }
        let settings = graph.settings.current
        if settings.offlineFirst, let file = graph.offline.fileFor(song.id) {
            return .file(file, mimeType: song.contentType)
        }
        guard let client = graph.auth.client else { return nil }
        let bitrate = settings.bitrateFor(metered: graph.network.isMetered)
        let format: String? = bitrate > 0 ? playableFormat(settings.preferredFormat) : nil
        guard let url = client.streamUrl(song.id, maxBitRate: bitrate > 0 ? bitrate : nil, format: format) else { return nil }
        if direct { return .direct(url) }
        let ext = format ?? ((song.suffix ?? "").isEmpty ? "mp3" : song.suffix!.lowercased())
        let key = "song:\(graph.auth.active?.id ?? ""):\(song.id):\(bitrate):\(format ?? "")"
        let cache = StreamCache.shared
        if let hit = cache.hit(for: key, fileExtension: ext) {
            return .file(hit, mimeType: format == nil ? song.contentType : nil)
        }
        let type = audioTypeIdentifier(suffix: ext, mimeType: format == nil ? song.contentType : nil)
        let target = settings.streamCacheMb > 0 ? cache.location(for: key, fileExtension: ext) : nil
        let resource = StreamingResource(remoteURL: url, contentType: type, cacheTarget: target, userAgent: "Kultr-iOS/\(appVersion)")
        return .stream(resource, direct: url)
    }
}

/**
 * One of the engine's two players: an AVQueuePlayer whose items carry
 * Kultr's audio tap (fades, bass swap, sweep, equaliser). Gapless hand-overs
 * queue the next item behind the current one.
 */
@MainActor
final class AVDeck: NSObject, Deck {
    let name: String
    let player = AVQueuePlayer()
    private let params = DeckParams()
    private let eq: EqState
    private let sources: DeckSources
    private weak var listener: DeckListener?

    private(set) var item: QueueItem?
    private var following: QueueItem?
    private var currentPlayerItem: AVPlayerItem?
    private var followingPlayerItem: AVPlayerItem?
    private var resources: [ObjectIdentifier: StreamingResource] = [:]
    private var itemObservers: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var playerObservers: [NSKeyValueObservation] = []

    private var token = 0
    private var wantPlay = false
    private var ended = false
    private var failed = false
    private var pendingSeekMs: Int64?
    private var startMs: Int64 = 0
    private var triedDirect = false
    private var isRadio = false

    private var level: Float = 0
    private var duck: Float = 1
    private var rate: Float = 1

    init(name: String, sources: DeckSources, eq: EqState) {
        self.name = name
        self.sources = sources
        self.eq = eq
        super.init()
        player.actionAtItemEnd = .pause
        player.automaticallyWaitsToMinimizeStalling = true
        playerObservers.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.changed() } }
        })
        playerObservers.append(player.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.currentItemChanged() } }
        })
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(itemEnded(_:)), name: .AVPlayerItemDidPlayToEndTime, object: nil)
        center.addObserver(self, selector: #selector(itemFailed(_:)), name: .AVPlayerItemFailedToPlayToEndTime, object: nil)
    }

    // ----------------------------------------------------------- state --

    var status: DeckStatus {
        if failed { return .error }
        guard item != nil else { return .idle }
        if ended { return .ended }
        guard let current = currentPlayerItem, current.status == .readyToPlay, pendingSeekMs == nil else { return .buffering }
        if wantPlay && player.timeControlStatus == .waitingToPlayAtSpecifiedRate { return .buffering }
        return .ready
    }

    var positionMs: Int64 {
        if ended { return max(0, durationMs) }
        if let pendingSeekMs { return pendingSeekMs }
        guard let current = currentPlayerItem else { return 0 }
        let seconds = CMTimeGetSeconds(current.currentTime())
        return seconds.isFinite ? Int64(seconds * 1000) : 0
    }

    var durationMs: Int64 {
        guard let current = currentPlayerItem else { return -1 }
        let seconds = CMTimeGetSeconds(current.duration)
        return seconds.isFinite && seconds > 0 ? Int64(seconds * 1000) : -1
    }

    var bufferedPositionMs: Int64 {
        guard let current = currentPlayerItem else { return 0 }
        let now = current.currentTime()
        for value in current.loadedTimeRanges {
            let range = value.timeRangeValue
            if CMTimeRangeContainsTime(range, time: now) {
                let end = CMTimeGetSeconds(CMTimeRangeGetEnd(range))
                return end.isFinite ? Int64(end * 1000) : positionMs
            }
        }
        return positionMs
    }

    var isPlaying: Bool {
        player.currentItem != nil && player.timeControlStatus == .playing
    }

    private func changed() {
        listener?.onStatusChanged(self)
    }

    // --------------------------------------------------------- loading --

    func load(_ item: QueueItem, startMs: Int64) {
        token += 1
        teardown()
        self.item = item
        following = nil
        ended = false
        failed = false
        wantPlay = false
        triedDirect = false
        pendingSeekMs = startMs > 0 ? startMs : nil
        self.startMs = startMs
        isRadio = item.song.isRadio
        player.pause()
        applyLevel()
        guard let source = sources.source(for: item) else {
            fail("Sign in to a server to play this.")
            return
        }
        prepare(source, for: item, token: token)
    }

    private func prepare(_ source: DeckSource, for queued: QueueItem, token expected: Int) {
        Task { [weak self] in
            guard let self else { return }
            let built = await self.makePlayerItem(source)
            guard self.token == expected, self.item?.uid == queued.uid else {
                built?.1?.invalidate()
                return
            }
            guard let built else {
                self.sourceFailed(nil)
                return
            }
            self.install(built.0, resource: built.1)
        }
    }

    /** Build an item for [source], with the tap on its audio track where one can go. */
    private func makePlayerItem(_ source: DeckSource) async -> (AVPlayerItem, StreamingResource?)? {
        let asset: AVURLAsset
        var resource: StreamingResource?
        switch source {
        case .radio(let url):
            let item = AVPlayerItem(url: url)
            return (item, nil)
        case .file(let url, let mime):
            let known = ["mp3", "m4a", "m4b", "mp4", "aac", "flac", "wav", "aif", "aiff", "caf", "alac"]
            if let mime, !known.contains(url.pathExtension.lowercased()) {
                asset = AVURLAsset(url: url, options: [AVURLAssetOverrideMIMETypeKey: mime])
            } else {
                asset = AVURLAsset(url: url)
            }
        case .stream(let streaming, _):
            asset = streaming.asset
            resource = streaming
        case .direct(let url):
            asset = AVURLAsset(url: url)
        }
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio), let track = tracks.first else {
            resource?.invalidate()
            return nil
        }
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.audioTimePitchAlgorithm = .spectral
        playerItem.audioMix = DeckTap.audioMix(for: track, processor: TapProcessor(params: params, eq: eq))
        return (playerItem, resource)
    }

    private func install(_ playerItem: AVPlayerItem, resource: StreamingResource?) {
        currentPlayerItem = playerItem
        if let resource { resources[ObjectIdentifier(playerItem)] = resource }
        observe(playerItem)
        player.removeAllItems()
        player.insert(playerItem, after: nil)
        player.actionAtItemEnd = .pause
        applyLevel()
        if playerItem.status == .readyToPlay { ready(playerItem) }
        changed()
    }

    private func observe(_ playerItem: AVPlayerItem) {
        itemObservers[ObjectIdentifier(playerItem)] = playerItem.observe(\.status, options: [.new]) { [weak self, weak playerItem] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let playerItem else { return }
                    self.itemStatusChanged(playerItem)
                }
            }
        }
    }

    private func itemStatusChanged(_ playerItem: AVPlayerItem) {
        switch playerItem.status {
        case .readyToPlay:
            if playerItem === currentPlayerItem { ready(playerItem) }
        case .failed:
            if playerItem === currentPlayerItem {
                sourceFailed(playerItem.error)
            } else if playerItem === followingPlayerItem {
                dropFollowing()
            }
        default:
            break
        }
    }

    /** The current item can play: apply a pending seek, then resume if wanted. */
    private func ready(_ playerItem: AVPlayerItem) {
        if let target = pendingSeekMs {
            let expected = token
            playerItem.seek(to: CMTime(value: target, timescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.token == expected else { return }
                        self.pendingSeekMs = nil
                        if self.wantPlay { self.startPlayer() }
                        self.changed()
                    }
                }
            }
            return
        }
        if wantPlay { startPlayer() }
        changed()
    }

    /** A source did not work; the cached stream falls back to a plain one once. */
    private func sourceFailed(_ error: Error?) {
        guard let queued = item else { return }
        if !triedDirect, !isRadio, let direct = sources.source(for: queued, direct: true), case .direct = direct {
            let hadCache = currentPlayerItem.map { resources[ObjectIdentifier($0)] != nil } ?? true
            if hadCache {
                triedDirect = true
                let position = currentPlayerItem.map { _ in positionMs } ?? startMs
                teardown()
                pendingSeekMs = position > 0 ? position : nil
                prepare(direct, for: queued, token: token)
                return
            }
        }
        fail(describe(error))
    }

    private func fail(_ message: String) {
        failed = true
        listener?.onError(self, message: message)
        changed()
    }

    private func describe(_ error: Error?) -> String {
        let title = item?.song.title ?? "this track"
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost:
                return "The connection to your server dropped while streaming."
            case .fileDoesNotExist:
                return "The offline copy of “\(title)” is missing."
            default:
                return "The server refused to stream “\(title)”."
            }
        }
        if let error = error as? NetworkError { return error.message }
        let ns = error.map { $0 as NSError }
        if ns?.domain == AVFoundationErrorDomain {
            return "This iPhone cannot play “\(title)”. Try a transcode format in Settings → Audio."
        }
        return ns.map { "Playback failed: \($0.localizedDescription)" } ?? "This iPhone cannot play “\(title)”. Try a transcode format in Settings → Audio."
    }

    // ------------------------------------------------------- transport --

    private func startPlayer() {
        player.defaultRate = rate
        player.play()
        if abs(player.rate - rate) > 0.0001 && player.rate != 0 { player.rate = rate }
    }

    func play() {
        wantPlay = true
        guard !ended, let current = currentPlayerItem, current.status == .readyToPlay, pendingSeekMs == nil else {
            changed()
            return
        }
        startPlayer()
    }

    func pause() {
        wantPlay = false
        player.pause()
    }

    func seekTo(_ positionMs: Int64) {
        ended = false
        guard let current = currentPlayerItem, current.status == .readyToPlay, pendingSeekMs == nil else {
            pendingSeekMs = positionMs
            return
        }
        pendingSeekMs = positionMs
        let expected = token
        current.seek(to: CMTime(value: positionMs, timescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.token == expected else { return }
                    self.pendingSeekMs = nil
                    if self.wantPlay { self.startPlayer() }
                    self.changed()
                }
            }
        }
    }

    func stop() {
        token += 1
        wantPlay = false
        item = nil
        following = nil
        ended = false
        failed = false
        pendingSeekMs = nil
        player.pause()
        teardown()
    }

    private func teardown() {
        player.removeAllItems()
        for resource in resources.values { resource.invalidate() }
        resources = [:]
        itemObservers = [:]
        currentPlayerItem = nil
        followingPlayerItem = nil
    }

    // ---------------------------------------------------------- gapless --

    func setNext(_ next: QueueItem?) {
        dropFollowing()
        guard let next, item != nil, !isRadio, let source = sources.source(for: next) else { return }
        following = next
        let expected = token
        Task { [weak self] in
            guard let self else { return }
            let built = await self.makePlayerItem(source)
            guard self.token == expected, self.following?.uid == next.uid, let built,
                  let current = self.currentPlayerItem, self.player.items().contains(current)
            else {
                built?.1?.invalidate()
                if self.following?.uid == next.uid { self.following = nil }
                return
            }
            let playerItem = built.0
            self.followingPlayerItem = playerItem
            if let resource = built.1 { self.resources[ObjectIdentifier(playerItem)] = resource }
            self.observe(playerItem)
            self.player.insert(playerItem, after: current)
            self.player.actionAtItemEnd = .advance
        }
    }

    private func dropFollowing() {
        if let pending = followingPlayerItem {
            player.remove(pending)
            resources.removeValue(forKey: ObjectIdentifier(pending))?.invalidate()
            itemObservers[ObjectIdentifier(pending)] = nil
        }
        following = nil
        followingPlayerItem = nil
        player.actionAtItemEnd = .pause
    }

    private func currentItemChanged() {
        guard let now = player.currentItem, now === followingPlayerItem, let next = following else { return }
        if let old = currentPlayerItem {
            resources.removeValue(forKey: ObjectIdentifier(old))?.invalidate()
            itemObservers[ObjectIdentifier(old)] = nil
        }
        currentPlayerItem = now
        followingPlayerItem = nil
        following = nil
        item = next
        ended = false
        player.actionAtItemEnd = .pause
        listener?.onAutoAdvanced(self, item: next)
    }

    @objc nonisolated private func itemEnded(_ note: Notification) {
        let object = note.object as AnyObject?
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let object, object === self.currentPlayerItem else { return }
                // With a follower queued, the player moves on by itself.
                if self.followingPlayerItem != nil { return }
                self.ended = true
                self.changed()
            }
        }
    }

    @objc nonisolated private func itemFailed(_ note: Notification) {
        let object = note.object as AnyObject?
        let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let object, object === self.currentPlayerItem else { return }
                self.fail(self.describe(error))
            }
        }
    }

    // ------------------------------------------------------------ sound --

    private func applyLevel() {
        let gain = level * duck
        params.set { $0.targetGain = gain }
        player.volume = isRadio ? min(1, gain) : 1
    }

    func setLevel(_ level: Float) {
        self.level = level
        applyLevel()
    }

    /** Lower everything while another app briefly needs the speaker. */
    func setDuck(_ duck: Float) {
        self.duck = duck
        applyLevel()
    }

    func setRate(_ rate: Float) {
        // Small steps are inaudible; do not churn the time-stretcher for them.
        let snap = rate == 1 && self.rate != 1
        guard abs(rate - self.rate) >= 0.0015 || snap else { return }
        self.rate = rate
        player.defaultRate = rate
        if player.rate != 0 { player.rate = rate }
    }

    func setBassDb(_ db: Float) {
        params.set { $0.bassDb = db }
    }

    func setSweepHz(_ hz: Float) {
        params.set { $0.sweepHz = hz }
    }

    func setListener(_ listener: DeckListener?) {
        self.listener = listener
    }
}
