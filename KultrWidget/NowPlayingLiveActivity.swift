import ActivityKit
import SwiftUI
import WidgetKit

/** The Live Activity: the track, its progress, and a countdown to the next mix. */
struct NowPlayingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowPlayingAttributes.self) { context in
            LockScreenActivity(state: context.state)
                .activityBackgroundTint(Color.activityPage)
                .activitySystemActionForegroundColor(Color.activityInk)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityArtwork(size: 52)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.title).font(.headline).lineLimit(1)
                        Text(state.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Button(intent: TogglePlaybackIntent()) {
                        Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundStyle(Color.activityOrange)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        TrackBar(state: state)
                        MixLine(state: state)
                    }
                }
            } compactLeading: {
                ActivityArtwork(size: 24)
            } compactTrailing: {
                if state.isPlaying, let mixAt = state.mixAt, mixAt > Date() {
                    Text(timerInterval: Date()...mixAt, countsDown: true)
                        .monospacedDigit()
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.activityOrange)
                        .frame(maxWidth: 44)
                } else {
                    Image(systemName: state.isPlaying ? "waveform" : "pause.fill")
                        .foregroundStyle(Color.activityOrange)
                }
            } minimal: {
                ActivityArtwork(size: 22)
            }
            .keylineTint(Color.activityOrange)
        }
    }
}

private struct LockScreenActivity: View {
    let state: NowPlayingAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ActivityArtwork(size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    if let station = state.station {
                        Text(station.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.activityOrange)
                            .lineLimit(1)
                    }
                    Text(state.title)
                        .font(.headline)
                        .foregroundStyle(Color.activityInk)
                        .lineLimit(1)
                    Text(state.artist)
                        .font(.subheadline)
                        .foregroundStyle(Color.activityInk.opacity(0.65))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(intent: TogglePlaybackIntent()) {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(Color.activityPage)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.activityInk))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(state.isPlaying ? "Pause" : "Play")
            }
            TrackBar(state: state)
            MixLine(state: state)
        }
        .padding(16)
    }
}

/** How far into the track: runs by itself while playing. */
private struct TrackBar: View {
    let state: NowPlayingAttributes.ContentState

    var body: some View {
        Group {
            if state.isPlaying && state.durationMs > 0 && state.endsAt > Date() {
                ProgressView(timerInterval: state.startedAt...state.endsAt, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            } else {
                ProgressView(value: state.progress)
            }
        }
        .progressViewStyle(.linear)
        .tint(Color.activityOrange)
    }
}

/** "Mixing into Paper Moons in 0:12", or what's next when no mix is coming. */
private struct MixLine: View {
    let state: NowPlayingAttributes.ContentState

    var body: some View {
        if let next = state.next {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.merge")
                    .foregroundStyle(Color.activityOrange)
                if state.isPlaying, let mixAt = state.mixAt, mixAt > Date() {
                    Text("\(state.mix ?? "Mix") into \(next) in")
                        .lineLimit(1)
                    Text(timerInterval: Date()...mixAt, countsDown: true)
                        .monospacedDigit()
                        .foregroundStyle(Color.activityOrange)
                        .frame(maxWidth: 52, alignment: .leading)
                } else {
                    Text("Next: \(next)").lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.activityInk.opacity(0.8))
        }
    }
}

/** The cover the app saved for the widget, or a note on orange. */
private struct ActivityArtwork: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let image = SharedStore.artwork() {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.activityOrange
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.45, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
    }
}

private extension Color {
    static let activityOrange = Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 0x7A / 255.0, blue: 0x3D / 255.0, alpha: 1)
            : UIColor(red: 0xC2 / 255.0, green: 0x41 / 255.0, blue: 0x0C / 255.0, alpha: 1) })
    static let activityInk = Color(UIColor { $0.userInterfaceStyle == .dark ? .white : UIColor(red: 0x1F / 255.0, green: 0x1A / 255.0, blue: 0x14 / 255.0, alpha: 1) })
    static let activityPage = Color(UIColor {
        $0.userInterfaceStyle == .dark
            ? UIColor(red: 0x1C / 255.0, green: 0x1A / 255.0, blue: 0x17 / 255.0, alpha: 1)
            : UIColor(red: 0xF6 / 255.0, green: 0xF0 / 255.0, blue: 0xE5 / 255.0, alpha: 1)
    })
}
