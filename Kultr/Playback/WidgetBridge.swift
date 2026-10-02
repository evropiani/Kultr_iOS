import Foundation
import Observation
import UIKit
import WidgetKit

/** What the widget's buttons do, in the app. */
@MainActor
enum KultrIntentActions {
    static func toggle() { AppGraph.shared.player.toggle() }
    static func next() { AppGraph.shared.player.next() }
    static func previous() { AppGraph.shared.player.previous() }
    static func toggleShuffle() {
        let player = AppGraph.shared.player
        player.setShuffle(!player.state.shuffle)
    }
    static func cycleRepeat() { AppGraph.shared.player.cycleRepeat() }

    /**
     * Jumps to a song the widget listed. The queue may have changed since the
     * widget was drawn, so the song is looked for by id when it has moved.
     */
    static func playQueued(index: Int, songId: String) {
        let player = AppGraph.shared.player
        let queue = player.state.queue
        if queue.indices.contains(index), queue[index].song.id == songId {
            player.jumpTo(index)
        } else if let moved = queue.first(where: { $0.index > player.state.index && $0.song.id == songId })
            ?? queue.first(where: { $0.song.id == songId }) {
            player.jumpTo(moved.index)
        }
    }
}

/**
 * Keeps the Now Playing widget up to date: when the track, play/pause or the
 * position (after a seek) changes, writes what is playing and its artwork to
 * the shared container and asks iOS to redraw the widget. Between those, the
 * widget's progress bar runs by itself.
 */
@MainActor
@Observable
final class WidgetBridge {
    static let shared = WidgetBridge()

    /** The last snapshot, also kept here so the app can preview the widget without a shared container. */
    private(set) var snapshot: NowPlayingSnapshot?
    private(set) var artwork: UIImage?
    /** Covers of the songs up next, also for the app's own previews. */
    private(set) var queueArtwork: [String: UIImage] = [:]
    @ObservationIgnored private var artworkFor: String?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var queueArtworkTask: Task<Void, Never>?

    /** How many waiting songs the widgets are told about (the extra-large one lists the most). */
    static let upNextLimit = 6

    private init() {
        // A widget left saying "playing" after Kultr has quit would be wrong for good.
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let bridge = WidgetBridge.shared
                guard var stopped = bridge.snapshot, stopped.isPlaying else { return }
                stopped.positionMs += Int64(Date().timeIntervalSince(stopped.at) * 1000)
                stopped.isPlaying = false
                stopped.at = Date()
                SharedStore.write(stopped, artwork: nil)
                bridge.reload()
            }
        }
    }

    /**
     * [artworkURL] comes from the player: this must not reach for
     * `AppGraph.shared`, because the first update can come while the graph is
     * still being built (restoring the last queue at launch), and touching it
     * then crashes Kultr on every launch. [queueArtworkURLs] are the covers
     * of the songs waiting, by song id, for the large widgets.
     */
    func update(_ state: PlayerUiState, positionMs: Int64, artworkURL: URL?, queueArtworkURLs: [String: URL] = [:]) {
        guard let song = state.current else {
            if snapshot != nil {
                snapshot = nil
                artwork = nil
                artworkFor = nil
                queueArtworkTask?.cancel()
                SharedStore.write(nil, artwork: nil)
                SharedStore.keepQueueArtwork([])
                reload()
            }
            return
        }
        let waiting = state.upNext.prefix(Self.upNextLimit).map { entry in
            UpNextSong(
                songId: entry.song.id,
                title: entry.song.title,
                artist: entry.song.artist ?? "",
                index: entry.index,
                hasArtwork: entry.song.artworkId != nil
            )
        }
        let next = NowPlayingSnapshot(
            songId: song.id,
            title: song.title,
            artist: song.artist ?? "",
            album: song.album ?? "",
            isPlaying: state.playWhenReady,
            positionMs: max(0, positionMs),
            durationMs: state.durationMs,
            at: Date(),
            accent: snapshot?.songId == song.id ? (snapshot?.accent ?? 0x7C8CFF) : 0x7C8CFF,
            hasArtwork: song.artworkId != nil,
            upNext: Array(waiting),
            upNextCount: state.upNext.count,
            shuffle: state.shuffle,
            repeatMode: state.repeatMode.rawValue
        )
        guard changedEnough(from: snapshot, to: next) else { return }
        let queueChanged = snapshot?.upNext != next.upNext
        snapshot = next
        SharedStore.write(next, artwork: nil)
        reload()
        if artworkFor != song.id { loadArtwork(for: song, from: artworkURL) }
        if queueChanged { loadQueueArtwork(next.upNext ?? [], queueArtworkURLs) }
    }

    /** A new track, play/pause, a new length, or a position the widget's own clock would not show. */
    private func changedEnough(from old: NowPlayingSnapshot?, to new: NowPlayingSnapshot) -> Bool {
        guard let old else { return true }
        if old.songId != new.songId || old.isPlaying != new.isPlaying || old.durationMs != new.durationMs || old.title != new.title {
            return true
        }
        if old.upNext != new.upNext || old.upNextCount != new.upNextCount || old.shuffle != new.shuffle || old.repeatMode != new.repeatMode {
            return true
        }
        let expected = old.isPlaying ? old.positionMs + Int64(new.at.timeIntervalSince(old.at) * 1000) : old.positionMs
        return abs(expected - new.positionMs) > 3_000
    }

    private func loadArtwork(for song: Song, from url: URL?) {
        artworkFor = song.id
        artworkTask?.cancel()
        let songId = song.id
        guard let url else {
            artwork = nil
            return
        }
        artworkTask = Task { [weak self] in
            async let image = ImageLoader.shared.image(url, pixelSize: 300)
            async let colour = ImageLoader.shared.dominantColor(url)
            let (loaded, accent) = await (image, colour)
            guard let self, !Task.isCancelled, self.snapshot?.songId == songId else { return }
            self.artwork = loaded
            if let accent { self.snapshot?.accent = accent & 0xFFFFFF }
            let jpeg = loaded?.jpegData(compressionQuality: 0.85)
            SharedStore.write(self.snapshot, artwork: jpeg)
            self.reload()
        }
    }

    /** Small covers for the songs waiting, for the large widgets: the missing ones fetched, the rest kept. */
    private func loadQueueArtwork(_ songs: [UpNextSong], _ urls: [String: URL]) {
        queueArtworkTask?.cancel()
        let ids = Set(songs.map(\.songId))
        SharedStore.keepQueueArtwork(ids)
        queueArtwork = queueArtwork.filter { ids.contains($0.key) }
        let missing = songs
            .filter { $0.hasArtwork && (queueArtwork[$0.songId] == nil || !SharedStore.hasQueueArtwork($0.songId)) }
            .compactMap { song in urls[song.songId].map { (song.songId, $0) } }
        guard !missing.isEmpty else { return }
        queueArtworkTask = Task { [weak self] in
            var wrote = false
            for (songId, url) in missing {
                guard !Task.isCancelled else { return }
                guard let image = await ImageLoader.shared.image(url, pixelSize: 96) else { continue }
                self?.queueArtwork[songId] = image
                if let jpeg = image.jpegData(compressionQuality: 0.8) { SharedStore.writeQueueArtwork(songId, jpeg) }
                wrote = true
            }
            if wrote, !Task.isCancelled { self?.reload() }
        }
    }

    private func reload() {
        WidgetCenter.shared.reloadTimelines(ofKind: "app.kultr.ios.nowplaying")
    }
}
