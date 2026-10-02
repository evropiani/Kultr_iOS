import SwiftUI
import WidgetKit

/** Kultr's widgets. The app reloads them when the track or play/pause changes. */
@main
struct KultrWidgets: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
    }
}

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: NowPlayingSnapshot?
    let artwork: UIImage?
    /** Covers of the songs up next, for the large sizes. */
    var queueArtwork: [String: UIImage] = [:]
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: Date(), snapshot: Self.sample, artwork: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        let stored = SharedStore.read()
        let snapshot = stored ?? (context.isPreview ? Self.sample : nil)
        completion(NowPlayingEntry(date: Date(), snapshot: snapshot, artwork: SharedStore.artwork(), queueArtwork: Self.queueArtwork(snapshot, context)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        let snapshot = SharedStore.read()
        let entry = NowPlayingEntry(date: Date(), snapshot: snapshot, artwork: SharedStore.artwork(), queueArtwork: Self.queueArtwork(snapshot, context))
        // While playing, look again once the track should have ended, in case
        // the app could not tell us about the next one in time.
        if let snapshot = entry.snapshot, snapshot.isPlaying, snapshot.endsAt > Date() {
            completion(Timeline(entries: [entry], policy: .after(snapshot.endsAt.addingTimeInterval(5))))
        } else {
            completion(Timeline(entries: [entry], policy: .never))
        }
    }

    /** Only the large sizes list what's next; the others don't need its covers. */
    private static func queueArtwork(_ snapshot: NowPlayingSnapshot?, _ context: Context) -> [String: UIImage] {
        guard context.family == .systemLarge || context.family == .systemExtraLarge, let songs = snapshot?.upNext else { return [:] }
        var images: [String: UIImage] = [:]
        for song in songs where song.hasArtwork {
            if let image = SharedStore.queueArtwork(song.songId) { images[song.songId] = image }
        }
        return images
    }

    private static let sample = NowPlayingSnapshot(
        songId: "", title: "Daniel", artist: "Natasha Beller", album: "Fairytale",
        isPlaying: true, positionMs: 72_000, durationMs: 243_000, at: Date(), accent: 0xC26282, hasArtwork: false,
        upNext: [
            UpNextSong(songId: "s1", title: "Paper Boats", artist: "Natasha Beller", index: 1, hasArtwork: false),
            UpNextSong(songId: "s2", title: "Glass Houses", artist: "Natasha Beller", index: 2, hasArtwork: false),
            UpNextSong(songId: "s3", title: "Northern Lights", artist: "Hollow Coves", index: 3, hasArtwork: false),
            UpNextSong(songId: "s4", title: "Harbour", artist: "Some Band", index: 4, hasArtwork: false),
            UpNextSong(songId: "s5", title: "Slow Motion", artist: "Natasha Beller", index: 5, hasArtwork: false),
            UpNextSong(songId: "s6", title: "Afterglow", artist: "Hollow Coves", index: 6, hasArtwork: false),
        ],
        upNextCount: 11,
        shuffle: false,
        repeatMode: "all"
    )
}

struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.kultr.ios.nowplaying", provider: NowPlayingProvider()) { entry in
            NowPlayingEntryView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("What Kultr is playing, with play, pause and skip; the large sizes also show what's up next.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .accessoryRectangular, .accessoryCircular])
        .contentMarginsDisabled()
    }
}

private struct NowPlayingEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NowPlayingEntry

    var body: some View {
        let isHome = family == .systemSmall || family == .systemMedium || family == .systemLarge || family == .systemExtraLarge
        let large = family == .systemLarge || family == .systemExtraLarge
        NowPlayingWidgetView(family: family, snapshot: entry.snapshot, artwork: entry.artwork, queueArtwork: entry.queueArtwork)
            .padding(isHome ? (large ? 16 : 14) : 0)
            .containerBackground(for: .widget) {
                if isHome {
                    NowPlayingWidgetBackground(snapshot: entry.snapshot, artwork: entry.artwork)
                } else {
                    Color.clear
                }
            }
    }
}
