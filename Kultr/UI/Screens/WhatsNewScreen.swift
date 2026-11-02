import SwiftUI

struct WhatsNewItem: Identifiable {
    let icon: String
    let title: String
    let text: String
    var id: String { title }
}

/**
 * What each version brings, shown once on the first start after updating to
 * it. Add an entry with every update; a version without one shows nothing.
 */
enum WhatsNew {
    static let notes: [String: [WhatsNewItem]] = [
        "1.4.2": [
            WhatsNewItem(
                icon: "dial.medium.fill",
                title: "Stations",
                text: "Endless mixes from your own library: Warm Up, Night Drive, Peak Hour, Deep Focus, Wind Down, Unplayed gems, Favourites and a station per decade. Turn the dial on the Stations page (the first shelf on Home) to choose; while one plays, turning it mixes into the next."
            ),
            WhatsNewItem(
                icon: "slider.horizontal.3",
                title: "Make your own",
                text: "Every station is a set of rules you can change: tempo, energy, key, genres, years, never played, favourites and rating, with a count of the tracks that fit."
            ),
            WhatsNewItem(
                icon: "platter.filled.top.iphone",
                title: "Live Activity",
                text: "The Lock Screen and the Dynamic Island show the track, its progress and a countdown to the next mix. Switch it off in Settings → Playback."
            ),
            WhatsNewItem(
                icon: "waveform.path",
                title: "Beat pulse",
                text: "The play button swells on the first beat of every bar, once InjeKt knows the track. Settings → Playback can make the phone tap along too."
            ),
        ],
        "1.4.1": [
            WhatsNewItem(
                icon: "arrow.counterclockwise.circle.fill",
                title: "Rediscover",
                text: "A new shelf on Home: albums you hearted or played a lot, and haven't played for a year."
            ),
            WhatsNewItem(
                icon: "calendar",
                title: "Your month in music",
                text: "Listening → Monthly recap shows how long you listened, your top tracks, albums and artists, and your longest day. Pick any month from the calendar button."
            ),
            WhatsNewItem(
                icon: "hand.tap.fill",
                title: "Gestures on the cover",
                text: "In the player, double-tap the cover to heart the track, hold it to mix into the next one, and swipe up for the queue. Settings → Playback changes what each does."
            ),
            WhatsNewItem(
                icon: "moon.zzz.fill",
                title: "Wind down",
                text: "With a sleep timer on, Karousel plays its calmest picks in the last 15 minutes. Switch it off in the sleep timer."
            ),
            WhatsNewItem(
                icon: "text.badge.plus",
                title: "Save the session",
                text: "The button at the top of Up next saves what you've played, or the whole queue, as a playlist."
            ),
            WhatsNewItem(
                icon: "rectangle.grid.1x2.fill",
                title: "Calmer loading",
                text: "Pages show their shape while they load instead of a spinner, and empty pages say what to do next."
            ),
        ],
    ]

    static func items(for version: String) -> [WhatsNewItem] { notes[version] ?? [] }
}

/** The page itself: a large title, a row per change and one button. */
struct WhatsNewScreen: View {
    @Environment(\.kultr) private var theme
    let onDone: () -> Void

    var body: some View {
        let c = theme.colors
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("What's new in Kultr")
                        .font(.largeTitle.bold())
                        .foregroundStyle(c.ink)
                    Text("Version \(appVersion)")
                        .font(KFont.bodyMedium)
                        .foregroundStyle(c.ink3)
                }
                .padding(.top, 32)
                ForEach(WhatsNew.items(for: appVersion)) { item in
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: item.icon)
                            .font(.title2)
                            .foregroundStyle(c.accent)
                            .frame(width: 36)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.headline)
                                .foregroundStyle(c.ink)
                            Text(item.text)
                                .font(.subheadline)
                                .foregroundStyle(c.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            WideButton(title: "Continue", icon: "checkmark", prominent: true, action: onDone)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .background(c.background)
        }
        .background(c.background)
    }
}
