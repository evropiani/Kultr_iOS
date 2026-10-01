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
    @ObservationIgnored private var artworkFor: String?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?

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

    func update(_ state: PlayerUiState, positionMs: Int64) {
        guard let song = state.current else {
            if snapshot != nil {
                snapshot = nil
                artwork = nil
                artworkFor = nil
                SharedStore.write(nil, artwork: nil)
                reload()
            }
            return
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
            hasArtwork: song.artworkId != nil
        )
        guard changedEnough(from: snapshot, to: next) else { return }
        snapshot = next
        SharedStore.write(next, artwork: nil)
        reload()
        if artworkFor != song.id { loadArtwork(for: song) }
    }

    /** A new track, play/pause, a new length, or a position the widget's own clock would not show. */
    private func changedEnough(from old: NowPlayingSnapshot?, to new: NowPlayingSnapshot) -> Bool {
        guard let old else { return true }
        if old.songId != new.songId || old.isPlaying != new.isPlaying || old.durationMs != new.durationMs || old.title != new.title {
            return true
        }
        let expected = old.isPlaying ? old.positionMs + Int64(new.at.timeIntervalSince(old.at) * 1000) : old.positionMs
        return abs(expected - new.positionMs) > 3_000
    }

    private func loadArtwork(for song: Song) {
        artworkFor = song.id
        artworkTask?.cancel()
        let songId = song.id
        guard let url = artworkUrl(song.artworkId, 300) else {
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

    private func reload() {
        WidgetCenter.shared.reloadTimelines(ofKind: "app.kultr.ios.nowplaying")
    }
}
