import AppIntents
import SwiftUI
import WidgetKit

/**
 * The Now Playing widget's faces, for the home screen (small and medium) and
 * the lock screen (rectangular and circular). Shared with the app only so it
 * can show them in its own previews.
 */
struct NowPlayingWidgetView: View {
    let family: WidgetFamily
    let snapshot: NowPlayingSnapshot?
    let artwork: UIImage?

    var body: some View {
        switch family {
        case .systemMedium: MediumFace(snapshot: snapshot, artwork: artwork)
        case .accessoryRectangular: RectangularFace(snapshot: snapshot)
        case .accessoryCircular: CircularFace(snapshot: snapshot)
        default: SmallFace(snapshot: snapshot, artwork: artwork)
        }
    }
}

/** Behind the home-screen faces: the artwork, blurred and darkened, tinted with its own colour. */
struct NowPlayingWidgetBackground: View {
    let snapshot: NowPlayingSnapshot?
    let artwork: UIImage?

    var body: some View {
        let accent = Color(rgb: snapshot?.accent ?? 0x7C8CFF)
        ZStack {
            LinearGradient(colors: [accent.opacity(0.9), Color(rgb: 0x0B0B12)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 28)
                    .opacity(0.75)
            }
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        }
    }
}

// ----------------------------------------------------------------- faces --

private struct SmallFace: View {
    let snapshot: NowPlayingSnapshot?
    let artwork: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                ArtworkTile(artwork: artwork, size: 64, radius: 12)
                Spacer(minLength: 4)
                ControlButton(intent: TogglePlaybackIntent(), icon: snapshot?.isPlaying == true ? "pause.fill" : "play.fill", size: 38, prominent: true)
            }
            Spacer(minLength: 6)
            Titles(snapshot: snapshot, titleSize: 14, lines: 2)
            ProgressLine(snapshot: snapshot)
                .padding(.top, 6)
        }
        .foregroundStyle(.white)
    }
}

private struct MediumFace: View {
    let snapshot: NowPlayingSnapshot?
    let artwork: UIImage?

    var body: some View {
        HStack(spacing: 14) {
            ArtworkTile(artwork: artwork, size: 128, radius: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(eyebrow)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 4)
                Titles(snapshot: snapshot, titleSize: 16, lines: 2)
                Spacer(minLength: 6)
                ProgressLine(snapshot: snapshot)
                HStack(spacing: 0) {
                    ControlButton(intent: PreviousTrackIntent(), icon: "backward.fill", size: 34, prominent: false)
                    Spacer(minLength: 0)
                    ControlButton(intent: TogglePlaybackIntent(), icon: snapshot?.isPlaying == true ? "pause.fill" : "play.fill", size: 42, prominent: true)
                    Spacer(minLength: 0)
                    ControlButton(intent: NextTrackIntent(), icon: "forward.fill", size: 34, prominent: false)
                }
                .padding(.top, 8)
            }
        }
        .foregroundStyle(.white)
    }

    private var eyebrow: String {
        guard let snapshot else { return "KULTR" }
        return snapshot.isPlaying ? "NOW PLAYING" : "PAUSED"
    }
}

private struct RectangularFace: View {
    let snapshot: NowPlayingSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(snapshot?.isPlaying == true ? "Now playing" : "Kultr", systemImage: snapshot?.isPlaying == true ? "waveform" : "music.note")
                .font(.system(size: 12, weight: .semibold))
                .widgetAccentable()
            Text(snapshot?.title ?? "Nothing playing")
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
            Text(snapshot?.artist ?? "Tap to open Kultr")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CircularFace: View {
    let snapshot: NowPlayingSnapshot?

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let snapshot, snapshot.isPlaying, snapshot.durationMs > 0, snapshot.endsAt > snapshot.startedAt {
                ProgressView(timerInterval: snapshot.startedAt...snapshot.endsAt, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    Image(systemName: "waveform")
                }
                .progressViewStyle(.circular)
                .widgetAccentable()
            } else {
                Gauge(value: snapshot?.progress ?? 0) {
                    EmptyView()
                } currentValueLabel: {
                    Image(systemName: snapshot == nil ? "music.note" : "pause.fill")
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
            }
        }
    }
}

// ----------------------------------------------------------------- parts --

private struct Titles: View {
    let snapshot: NowPlayingSnapshot?
    let titleSize: CGFloat
    let lines: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot?.title ?? "Nothing playing")
                .font(.system(size: titleSize, weight: .semibold))
                .lineLimit(lines)
            Text(subtitle)
                .font(.system(size: titleSize - 3))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
        }
    }

    private var subtitle: String {
        guard let snapshot else { return "Tap play to pick up where you left off" }
        return snapshot.artist.isEmpty ? snapshot.album : snapshot.artist
    }
}

private struct ArtworkTile: View {
    let artwork: UIImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .fullColorInAccentedMode()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.14)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.36, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }
}

/** A progress line that runs by itself while playing, so the widget needs no refreshes for it. */
private struct ProgressLine: View {
    let snapshot: NowPlayingSnapshot?

    var body: some View {
        Group {
            if let snapshot, snapshot.isPlaying, snapshot.durationMs > 0, snapshot.endsAt > snapshot.startedAt {
                ProgressView(timerInterval: snapshot.startedAt...snapshot.endsAt, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            } else {
                ProgressView(value: snapshot?.progress ?? 0)
            }
        }
        .progressViewStyle(.linear)
        .tint(.white)
        .opacity(snapshot == nil ? 0 : 1)
    }
}

/** A round button: frosted, or solid white for the main one. */
private struct ControlButton<Intent: AppIntent>: View {
    let intent: Intent
    let icon: String
    let size: CGFloat
    let prominent: Bool

    var body: some View {
        Button(intent: intent) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(prominent ? Color.black : Color.white)
                .frame(width: size, height: size)
                .background(Circle().fill(prominent ? Color.white : Color.white.opacity(0.16)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private extension Color {
    init(rgb: UInt32) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xff) / 255,
            green: Double((rgb >> 8) & 0xff) / 255,
            blue: Double(rgb & 0xff) / 255,
            opacity: 1
        )
    }
}

private extension Image {
    /** Keeps the artwork in colour when iOS tints the home screen. */
    @ViewBuilder
    func fullColorInAccentedMode() -> some View {
        if #available(iOS 18.0, *) {
            self.widgetAccentedRenderingMode(.fullColor)
        } else {
            self
        }
    }
}
