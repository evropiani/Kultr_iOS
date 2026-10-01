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
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: Date(), snapshot: Self.sample, artwork: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        let stored = SharedStore.read()
        completion(NowPlayingEntry(date: Date(), snapshot: stored ?? (context.isPreview ? Self.sample : nil), artwork: SharedStore.artwork()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        let entry = NowPlayingEntry(date: Date(), snapshot: SharedStore.read(), artwork: SharedStore.artwork())
        // While playing, look again once the track should have ended, in case
        // the app could not tell us about the next one in time.
        if let snapshot = entry.snapshot, snapshot.isPlaying, snapshot.endsAt > Date() {
            completion(Timeline(entries: [entry], policy: .after(snapshot.endsAt.addingTimeInterval(5))))
        } else {
            completion(Timeline(entries: [entry], policy: .never))
        }
    }

    private static let sample = NowPlayingSnapshot(
        songId: "", title: "Daniel", artist: "Natasha Beller", album: "Fairytale",
        isPlaying: true, positionMs: 72_000, durationMs: 243_000, at: Date(), accent: 0xC26282, hasArtwork: false
    )
}

struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.kultr.ios.nowplaying", provider: NowPlayingProvider()) { entry in
            NowPlayingEntryView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("What Kultr is playing, with play, pause and skip.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
        .contentMarginsDisabled()
    }
}

private struct NowPlayingEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NowPlayingEntry

    var body: some View {
        let isHome = family == .systemSmall || family == .systemMedium
        NowPlayingWidgetView(family: family, snapshot: entry.snapshot, artwork: entry.artwork)
            .padding(isHome ? 14 : 0)
            .containerBackground(for: .widget) {
                if isHome {
                    NowPlayingWidgetBackground(snapshot: entry.snapshot, artwork: entry.artwork)
                } else {
                    Color.clear
                }
            }
    }
}
