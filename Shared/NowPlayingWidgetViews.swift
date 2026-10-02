import AppIntents
import SwiftUI
import WidgetKit

/**
 * The Now Playing widget's faces, for the home screen (small, medium, large
 * and, on iPad, extra large) and the lock screen (rectangular and circular).
 * Shared with the app only so it can show them in its own previews.
 */
struct NowPlayingWidgetView: View {
    let family: WidgetFamily
    let snapshot: NowPlayingSnapshot?
    let artwork: UIImage?
    /** Small covers of the songs under "Up next", by song id. */
    var queueArtwork: [String: UIImage] = [:]

    var body: some View {
        switch family {
        case .systemMedium: MediumFace(snapshot: snapshot, artwork: artwork)
        case .systemLarge: LargeFace(snapshot: snapshot, artwork: artwork, queueArtwork: queueArtwork)
        case .systemExtraLarge: ExtraLargeFace(snapshot: snapshot, artwork: artwork, queueArtwork: queueArtwork)
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

/**
 * Large: the song with its artwork, a running clock and every control
 * (shuffle and repeat too), then the next songs in the queue — tap one to
 * play it.
 */
private struct LargeFace: View {
    let snapshot: NowPlayingSnapshot?
    let artwork: UIImage?
    let queueArtwork: [String: UIImage]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                ArtworkTile(artwork: artwork, size: 84, radius: 15)
                VStack(alignment: .leading, spacing: 0) {
                    StateEyebrow(snapshot: snapshot)
                        .padding(.bottom, 4)
                    Titles(snapshot: snapshot, titleSize: 17, lines: 2)
                    AlbumLine(snapshot: snapshot)
                        .padding(.top, 3)
                }
                Spacer(minLength: 0)
            }
            TimeRow(snapshot: snapshot)
                .padding(.top, 12)
            TransportRow(snapshot: snapshot, playSize: 44, sideSize: 34, extras: true)
                .padding(.top, 6)
            UpNextList(snapshot: snapshot, queueArtwork: queueArtwork, maxRows: 3, rowHeight: 38)
                .padding(.top, 10)
        }
        .foregroundStyle(.white)
    }
}

/**
 * Extra large (iPad): the song and its controls on the left, a longer list
 * of what plays next on the right.
 */
private struct ExtraLargeFace: View {
    let snapshot: NowPlayingSnapshot?
    let artwork: UIImage?
    let queueArtwork: [String: UIImage]

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    ArtworkTile(artwork: artwork, size: 150, radius: 22)
                    VStack(alignment: .leading, spacing: 0) {
                        StateEyebrow(snapshot: snapshot)
                            .padding(.bottom, 6)
                        Titles(snapshot: snapshot, titleSize: 20, lines: 3)
                        AlbumLine(snapshot: snapshot)
                            .padding(.top, 4)
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 12)
                TimeRow(snapshot: snapshot)
                TransportRow(snapshot: snapshot, playSize: 52, sideSize: 40, extras: true)
                    .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(.white.opacity(0.16))
                .frame(width: 0.5)
            UpNextList(snapshot: snapshot, queueArtwork: queueArtwork, maxRows: 6, rowHeight: 42)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
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

private struct StateEyebrow: View {
    let snapshot: NowPlayingSnapshot?

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(1)
    }

    private var text: String {
        guard let snapshot else { return "KULTR" }
        return snapshot.isPlaying ? "NOW PLAYING" : "PAUSED"
    }
}

/** The album, when the artist line above didn't already use it. */
private struct AlbumLine: View {
    let snapshot: NowPlayingSnapshot?

    var body: some View {
        if let snapshot, !snapshot.artist.isEmpty, !snapshot.album.isEmpty {
            Text(snapshot.album)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
    }
}

/** The progress line with the time played and the time left, both running by themselves while playing. */
private struct TimeRow: View {
    let snapshot: NowPlayingSnapshot?

    var body: some View {
        VStack(spacing: 3) {
            ProgressLine(snapshot: snapshot)
            // Timer texts take all the width they're given; fixed widths keep them at the ends.
            HStack {
                elapsed
                    .frame(width: 64, alignment: .leading)
                Spacer(minLength: 8)
                remaining
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.7))
        }
        .opacity(snapshot == nil ? 0 : 1)
    }

    private var running: Bool {
        guard let snapshot else { return false }
        return snapshot.isPlaying && snapshot.durationMs > 0 && snapshot.endsAt > snapshot.startedAt
    }

    @ViewBuilder
    private var elapsed: some View {
        if let snapshot, running {
            Text(snapshot.startedAt, style: .timer)
                .multilineTextAlignment(.leading)
        } else {
            Text(clock(snapshot?.positionMs ?? 0))
        }
    }

    @ViewBuilder
    private var remaining: some View {
        if let snapshot, running {
            Text("-") + Text(timerInterval: snapshot.startedAt...snapshot.endsAt, countsDown: true)
        } else if let snapshot, snapshot.durationMs > 0 {
            Text("-" + clock(max(0, snapshot.durationMs - snapshot.positionMs)))
        } else {
            Text("")
        }
    }

    private func clock(_ ms: Int64) -> String {
        let total = Int(ms / 1000)
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}

/** Previous, play or pause, next; with [extras], shuffle and repeat on either side. */
private struct TransportRow: View {
    let snapshot: NowPlayingSnapshot?
    let playSize: CGFloat
    let sideSize: CGFloat
    let extras: Bool

    var body: some View {
        HStack(spacing: 0) {
            if extras {
                ToggleButton(intent: ToggleShuffleIntent(), icon: "shuffle", on: snapshot?.shuffle == true, size: sideSize)
                Spacer(minLength: 0)
            }
            ControlButton(intent: PreviousTrackIntent(), icon: "backward.fill", size: sideSize, prominent: false)
            Spacer(minLength: 0)
            ControlButton(intent: TogglePlaybackIntent(), icon: snapshot?.isPlaying == true ? "pause.fill" : "play.fill", size: playSize, prominent: true)
            Spacer(minLength: 0)
            ControlButton(intent: NextTrackIntent(), icon: "forward.fill", size: sideSize, prominent: false)
            if extras {
                Spacer(minLength: 0)
                ToggleButton(
                    intent: CycleRepeatIntent(),
                    icon: snapshot?.repeatMode == "one" ? "repeat.1" : "repeat",
                    on: (snapshot?.repeatMode ?? "off") != "off",
                    size: sideSize
                )
            }
        }
    }
}

/**
 * "Up next": the songs waiting in the queue, as many as fit (at most
 * [maxRows]), each a button that plays it. Says so when nothing waits.
 */
private struct UpNextList: View {
    let snapshot: NowPlayingSnapshot?
    let queueArtwork: [String: UIImage]
    let maxRows: Int
    let rowHeight: CGFloat

    var body: some View {
        let songs = snapshot?.upNext ?? []
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("UP NEXT")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 8)
                if let more = waitingLabel {
                    Text(more)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            if songs.isEmpty {
                empty
            } else {
                // As many rows as the space left holds, so none is cut in half.
                GeometryReader { proxy in
                    let fit = Int((proxy.size.height + rowSpacing) / (rowHeight + rowSpacing))
                    list(Array(songs.prefix(max(1, min(maxRows, fit)))))
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private let rowSpacing: CGFloat = 2

    private func list(_ songs: [UpNextSong]) -> some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(songs) { song in
                Button(intent: PlayQueuedSongIntent(index: song.index, songId: song.songId)) {
                    HStack(spacing: 10) {
                        Thumbnail(image: queueArtwork[song.songId], size: rowHeight - 6)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(song.title)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            if !song.artist.isEmpty {
                                Text(song.artist)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.62))
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(snapshot == nil ? "Nothing queued" : "Nothing after this song")
                .font(.system(size: 13, weight: .semibold))
            Text(snapshot?.repeatMode == "all"
                 ? "The queue starts again from the top."
                 : "Add songs in Kultr with Play next or Add to queue.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(2)
        }
        .padding(.top, 2)
    }

    /** How many songs wait in all. */
    private var waitingLabel: String? {
        guard let total = snapshot?.upNextCount, total > 0 else { return nil }
        return total == 1 ? "1 song" : "\(total) songs"
    }
}

private struct Thumbnail: View {
    let image: UIImage?
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .fullColorInAccentedMode()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.14)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
    }
}

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

/** Shuffle or repeat: dim when off, lit when on. */
private struct ToggleButton<Intent: AppIntent>: View {
    let intent: Intent
    let icon: String
    let on: Bool
    let size: CGFloat

    var body: some View {
        Button(intent: intent) {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(on ? Color.white : Color.white.opacity(0.5))
                .frame(width: size, height: size)
                .background(Circle().fill(on ? Color.white.opacity(0.24) : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon == "shuffle" ? "Shuffle" : "Repeat")
        .accessibilityValue(on ? "On" : "Off")
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
