import ActivityKit
import Foundation

/**
 * KultrPre 1.4.2 to 1.4.5 had a Live Activity; it is gone. This only ends one
 * left over from those builds, so the Lock Screen doesn't keep showing it.
 */
@MainActor
enum LiveActivityBridge {
    static func endLeftovers() {
        for leftover in Activity<NowPlayingAttributes>.activities {
            Task { await leftover.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
