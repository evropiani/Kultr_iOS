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
        "2.1.0": [
            WhatsNewItem(
                icon: "globe",
                title: "Kultr in German",
                text: "With your iPhone set to German, or Deutsch chosen for Kultr in the iPhone's Settings → Apps → Kultr → Language, the whole app is in German. Settings → Language takes you there."
            ),
            WhatsNewItem(
                icon: "text.magnifyingglass",
                title: "Commands in German",
                text: "Search understands German too: “spiele Nachtfahrt”, “zufällig” and an artist, “schlaf in 30 Minuten”, “weiter”, “öffne Einstellungen” or “plane eine Stunde”."
            ),
        ],
        "2.0.1": [
            WhatsNewItem(
                icon: "square.grid.2x2.fill",
                title: "Edit your widgets",
                text: "Hold a widget on Home for a menu: Edit widgets, Size, Add a widget and Remove. In 2.0.0, holding one did nothing."
            ),
            WhatsNewItem(
                icon: "switch.2",
                title: "Widgets in Settings",
                text: "Settings → Home page has a Widgets section: switch widgets off altogether, or add, remove, move and resize them."
            ),
        ],
        "2.0.0": [
            WhatsNewItem(
                icon: "dial.medium.fill",
                title: "Stations",
                text: "Endless mixes from your own library: Warm Up, Night Drive, Peak Hour, Deep Focus, Wind Down, Unplayed gems, Favourites and one per decade, the first shelf on Home. Turn the dial on the Stations page to choose; while one plays, turning it mixes into the next. Make your own from tempo, energy, key, genres, years, your tags and more."
            ),
            WhatsNewItem(
                icon: "waveform.path.ecg",
                title: "Energy planner",
                text: "Draw how the next hour should feel, calm to peak, and Kultr builds a set that follows your line, with tempos and keys that mix. Play it or keep it as a playlist. “Plan a set” on Home."
            ),
            WhatsNewItem(
                icon: "text.magnifyingglass",
                title: "Search does things",
                text: "Type “play Night Drive”, “shuffle” and an artist, “sleep in 30 minutes”, “next”, “open settings” or “plan an hour” and tap the orange row, or press Return. With Apple Intelligence on, say it your own way; it's read on the iPhone itself."
            ),
            WhatsNewItem(
                icon: "shippingbox.fill",
                title: "Crates",
                text: "Folders for albums, artists and tracks in Library → Crates. Hold anything and tap Add to crate, or let rules fill one, like “4 stars and up, added this year”. Each can be kept as a playlist on your server."
            ),
            WhatsNewItem(
                icon: "tag.fill",
                title: "Notes and tags",
                text: "Album and artist pages have Your notes: tags of your own and a note. Tap a tag to see everything with it. They stay on your phone, and in a settings backup."
            ),
            WhatsNewItem(
                icon: "wand.and.stars",
                title: "Kultr Studio",
                text: "Settings → Kultr Studio: the whole look in one place. Start from Cream, Night, Ember, Paper or Console, change colours, corners, glass and the playhead, and see it in the preview as you go."
            ),
            WhatsNewItem(
                icon: "square.stack.3d.up.fill",
                title: "Build your player",
                text: "Choose which parts of the player show and in what order, and write its info line yourself: {bpm} BPM{?key: · {key}} shows the key only when there is one."
            ),
            WhatsNewItem(
                icon: "link",
                title: "Share a look",
                text: "Send your style as a link or a file. Opening someone's link shows it first; you choose whether to use it."
            ),
            WhatsNewItem(
                icon: "square.grid.2x2.fill",
                title: "Widgets on Home",
                text: "Now playing, your listening this week, the next mix, a station, a crate or a shortcut, small, medium or large. Hold one to move or remove it, and add more."
            ),
            WhatsNewItem(
                icon: "arrow.counterclockwise.circle.fill",
                title: "Rediscover",
                text: "A Home shelf of albums you hearted or played a lot and haven't played for a year."
            ),
            WhatsNewItem(
                icon: "calendar",
                title: "Your month in music",
                text: "Listening → Monthly recap: how long you listened, your top tracks, albums and artists, and your longest day. Pick any month."
            ),
            WhatsNewItem(
                icon: "forward.end.fill",
                title: "Hold Next to mix",
                text: "Hold the player's Next button and Kultr mixes into the next track over the whole crossfade instead of skipping."
            ),
            WhatsNewItem(
                icon: "magnifyingglass.circle.fill",
                title: "A glass lens on the scrubber",
                text: "Drag along the progress bar and a lens shows the time large, with the beats around it."
            ),
            WhatsNewItem(
                icon: "moon.zzz.fill",
                title: "Wind down",
                text: "With a sleep timer, the last 15 minutes play Karousel's calmest picks first."
            ),
            WhatsNewItem(
                icon: "text.badge.plus",
                title: "Save the session",
                text: "The button at the top of Up next keeps what you've played, or the whole queue, as a playlist."
            ),
            WhatsNewItem(
                icon: "rectangle.grid.1x2.fill",
                title: "Calmer loading",
                text: "Pages show their shape while they load instead of a spinner, and empty pages say why and what to do."
            ),
            WhatsNewItem(
                icon: "clock.arrow.circlepath",
                title: "Update log",
                text: "Settings → About → Update log has what changed in every version, from 1.0.0 to now."
            ),
        ],
    ]

    static func items(for version: String) -> [WhatsNewItem] { notes[version] ?? [] }

    /**
     * Everything since [seen], newest first: this version's page, then each
     * release in between from the update log. With [seen] unknown, this
     * version only.
     */
    static func pages(since seen: String?) -> [WhatsNewPage] {
        let log = UpdateLogEntry.all
        var out: [WhatsNewPage] = []
        let current = items(for: appVersion)
        if !current.isEmpty {
            out.append(WhatsNewPage(version: appVersion, items: current, log: nil))
        } else if let entry = log.first(where: { $0.version == appVersion }) {
            out.append(WhatsNewPage(version: appVersion, items: [], log: entry))
        }
        guard let seen else { return out }
        for entry in log where entry.version != appVersion
            && Versions.isNewer(entry.version, than: seen)
            && !Versions.isNewer(entry.version, than: appVersion) {
            out.append(WhatsNewPage(version: entry.version, items: [], log: entry))
        }
        return out
    }
}

/** One version on the What's new page. */
struct WhatsNewPage: Identifiable {
    let version: String
    /** The rows with icons, for a version that has them. */
    let items: [WhatsNewItem]
    /** Otherwise its release notes. */
    let log: UpdateLogEntry?
    var id: String { version }
}

/**
 * The page itself: this version's changes, then those of every release since
 * the one you last saw, and one button.
 */
struct WhatsNewScreen: View {
    @Environment(\.kultr) private var theme
    let onDone: () -> Void

    var body: some View {
        let c = theme.colors
        let pages = WhatsNew.pages(since: AppGraph.shared.ui.whatsNewSeen)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("What's new in Kultr")
                        .font(.largeTitle.bold())
                        .foregroundStyle(c.ink)
                    Text(pages.count > 1 ? "Version \(appVersion), and everything since \(pages.last?.version ?? appVersion)" : "Version \(appVersion)")
                        .font(KFont.bodyMedium)
                        .foregroundStyle(c.ink3)
                }
                .padding(.top, 32)
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    if index > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            if index == 1 {
                                Text("Also new since you last updated")
                                    .font(KFont.bodySmall.weight(.semibold))
                                    .foregroundStyle(c.accent)
                            }
                            Text("Kultr \(page.version)")
                                .font(.title2.bold())
                                .foregroundStyle(c.ink)
                        }
                        .padding(.top, 8)
                    }
                    ForEach(page.items) { item in
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: item.icon)
                                .font(.title2)
                                .foregroundStyle(c.accent)
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title.loc)
                                    .font(.headline)
                                    .foregroundStyle(c.ink)
                                Text(item.text.loc)
                                    .font(.subheadline)
                                    .foregroundStyle(c.ink2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if let log = page.log {
                        UpdateLogLines(entry: log)
                    }
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
