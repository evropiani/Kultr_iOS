import ActivityKit
import Foundation
import UIKit

/**
 * Keeps the Live Activity in step with the player: started when music starts
 * with Kultr in front (iOS allows no other time), updated when the track,
 * play/pause, the next track or the planned mix changes, and ended when the
 * queue is cleared or Kultr quits. Its clocks run by themselves in between.
 */
@MainActor
final class LiveActivityBridge {
    static let shared = LiveActivityBridge()

    private var activity: Activity<NowPlayingAttributes>?
    private var last: NowPlayingAttributes.ContentState?

    private init() {
        // One from before a crash or a forced quit would say "playing" for hours.
        for leftover in Activity<NowPlayingAttributes>.activities {
            Task { await leftover.end(nil, dismissalPolicy: .immediate) }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { LiveActivityBridge.shared.end() }
        }
    }

    /**
     * [plan] is InjeKt's plan out of the current track, once made (about half
     * a minute before it ends); before that the mix is expected a crossfade's
     * length before the end.
     */
    func update(_ state: PlayerUiState, positionMs: Int64, plan: TransitionPlan?, settings: Settings, station: Station?) {
        guard settings.liveActivity, let song = state.current, !state.ended else {
            end()
            return
        }
        let now = Date()
        let position = max(0, positionMs)
        let next = state.upNext.first?.song
        var mixAt: Date?
        var mix: String?
        if let next, state.durationMs > 0 {
            if let plan {
                let rate = plan.outgoingRate > 0 ? plan.outgoingRate : 1
                mixAt = now.addingTimeInterval(max(0, plan.startAt - Double(position) / 1000) / rate)
                mix = Self.describe(plan)
            } else if !next.isRadio {
                let fade = settings.crossfadeEnabled ? settings.crossfadeSeconds : 0
                mixAt = now.addingTimeInterval(max(0, Double(state.durationMs - position) / 1000 - fade))
                mix = settings.injektEnabled ? "Mix" : (fade > 0 ? "Crossfade" : "On")
            }
        }
        let content = NowPlayingAttributes.ContentState(
            songId: song.id,
            title: song.title,
            artist: song.artist ?? "",
            isPlaying: state.playWhenReady,
            startedAt: now.addingTimeInterval(-Double(position) / 1000),
            durationMs: state.durationMs,
            positionMs: position,
            next: next?.title,
            mixAt: mixAt,
            mix: mix,
            station: station?.name
        )
        guard changedEnough(from: last, to: content) else { return }
        last = content
        let staleAt = content.isPlaying ? content.endsAt.addingTimeInterval(120) : now.addingTimeInterval(30 * 60)
        let payload = ActivityContent(state: content, staleDate: staleAt)
        if let activity, activity.activityState == .active {
            Task { await activity.update(payload) }
        } else if state.playWhenReady, UIApplication.shared.applicationState == .active,
                  ActivityAuthorizationInfo().areActivitiesEnabled {
            activity = try? Activity.request(attributes: NowPlayingAttributes(), content: payload, pushType: nil)
        }
    }

    func end() {
        last = nil
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /** Anything a viewer would notice; small drifts in the clocks are not. */
    private func changedEnough(from old: NowPlayingAttributes.ContentState?, to new: NowPlayingAttributes.ContentState) -> Bool {
        guard let old else { return true }
        if old.songId != new.songId || old.isPlaying != new.isPlaying || old.next != new.next || old.mix != new.mix
            || old.station != new.station || old.durationMs != new.durationMs || old.title != new.title {
            return true
        }
        if new.isPlaying && abs(old.startedAt.timeIntervalSince(new.startedAt)) > 2 { return true }
        if !new.isPlaying && abs(old.positionMs - new.positionMs) > 2_000 { return true }
        switch (old.mixAt, new.mixAt) {
        case (nil, nil): return false
        case let (a?, b?): return abs(a.timeIntervalSince(b)) > 2
        default: return true
        }
    }

    private static func describe(_ plan: TransitionPlan) -> String {
        switch plan.type {
        case .blend: return "Beat-matched blend"
        case .sweep: return "Sweep"
        case .crossfade: return "Crossfade"
        case .gapless: return "Straight"
        case .cut: return "Cut"
        }
    }
}
