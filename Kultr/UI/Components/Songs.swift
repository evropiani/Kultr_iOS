import Observation
import SwiftUI

/** An extra entry for a song's menu, for screen-specific actions. */
struct MenuAction: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let action: () -> Void
}

/** Multi-select across a list of tracks. Long-press starts it. */
@MainActor
@Observable
final class SongSelection {
    private(set) var ids: [String] = []

    var active: Bool { !ids.isEmpty }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    func toggle(_ id: String) {
        if let at = ids.firstIndex(of: id) {
            ids.remove(at: at)
        } else {
            ids.append(id)
        }
    }

    func clear() { ids = [] }

    func selectAll(_ songs: [Song]) {
        var seen = Set<String>()
        ids = songs.map { $0.id }.filter { seen.insert($0).inserted }
    }

    func picked(_ songs: [Song]) -> [Song] {
        let set = Set(ids)
        var seen = Set<String>()
        return songs.filter { set.contains($0.id) && seen.insert($0.id).inserted }
    }
}

/** The menu entries for one song; used by the "…" button and anywhere else. */
struct SongMenuItems: View {
    let song: Song
    let downloaded: Bool
    var extra: [MenuAction] = []

    var body: some View {
        let actions = AppGraph.shared.actions
        Button { actions.play([song]) } label: { Label("Play", systemImage: "play.fill") }
        Button { actions.playNext([song]) } label: { Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") }
        Button { actions.enqueue([song]) } label: { Label("Add to queue", systemImage: "music.note.list") }
        if !song.isRadio {
            Button { actions.addToPlaylist([song]) } label: { Label("Add to playlist…", systemImage: "text.badge.plus") }
            if AppGraph.shared.ui.isStarred(song) {
                Button { actions.setFavourite(song, false) } label: { Label("Remove from favourites", systemImage: "heart") }
            } else {
                Button { actions.setFavourite(song, true) } label: { Label("Add to favourites", systemImage: "heart.fill") }
            }
            Button { actions.rate(song) } label: {
                Label((song.userRating ?? 0) > 0 ? "Rating: \(song.userRating!) ★" : "Rate…", systemImage: "star.fill")
            }
            Button { actions.startInjektSet(song) } label: { Label("Start an InjeKt set from here", systemImage: "sparkles") }
            Divider()
            if song.albumId != nil {
                Button { actions.openAlbum(song.albumId) } label: { Label("Go to album", systemImage: "opticaldisc") }
            }
            if song.artistId != nil {
                Button { actions.openArtist(song.artistId) } label: { Label("Go to artist", systemImage: "person.fill") }
            }
            if downloaded {
                Button(role: .destructive) { actions.removeDownloads([song]) } label: { Label("Remove download", systemImage: "trash") }
            } else {
                Button { actions.download([song], song.title) } label: { Label("Download", systemImage: "arrow.down.circle") }
            }
        }
        if !extra.isEmpty {
            Divider()
            ForEach(extra) { item in
                Button(action: item.action) { Label(item.label, systemImage: item.icon) }
            }
        }
    }
}

/** A "…" button that opens a song's menu. */
struct SongMenuButton: View {
    @Environment(\.kultr) private var theme
    let song: Song
    let downloaded: Bool
    var extra: [MenuAction] = []

    var body: some View {
        Menu {
            SongMenuItems(song: song, downloaded: downloaded, extra: extra)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.colors.ink3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More for \(song.title)")
    }
}

struct SongRow: View {
    @Environment(\.kultr) private var theme
    let song: Song
    var number: Int?
    var showArtwork = true
    var isCurrent = false
    var downloaded = false
    var selected = false
    var selecting = false
    var compact = false
    var extra: [MenuAction] = []
    let onTap: () -> Void
    /** Starts multi-select with this track; offered in its long-press menu. */
    var onSelect: (() -> Void)?

    var body: some View {
        let c = theme.colors
        let row = HStack(spacing: 0) {
            if selecting {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? c.accent : c.ink3)
                    .frame(width: 22)
                    .padding(.trailing, 12)
            }
            if showArtwork {
                ZStack {
                    Artwork(coverId: song.artworkId, size: compact ? 38 : 46)
                    if isCurrent {
                        RoundedRectangle(cornerRadius: theme.radii.sm, style: .continuous).fill(.black.opacity(0.45))
                        Image(systemName: "waveform").foregroundStyle(c.accent)
                    }
                }
                .frame(width: compact ? 38 : 46, height: compact ? 38 : 46)
            } else if let number {
                ZStack {
                    if isCurrent {
                        Image(systemName: "waveform").font(.system(size: 15)).foregroundStyle(c.accent)
                    } else {
                        Text("\(number)").font(KFont.bodyMedium).foregroundStyle(c.ink3)
                    }
                }
                .frame(width: 32)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(KFont.bodyLarge.weight(.medium))
                    .foregroundStyle(isCurrent ? c.accent : c.ink)
                    .lineLimit(1)
                let sub = [song.artist, showArtwork ? song.album : nil].compactMap { $0 }.joined(separator: " · ")
                if !sub.isEmpty {
                    Text(sub)
                        .font(KFont.bodySmall)
                        .foregroundStyle(c.ink3)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            if downloaded {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(c.ink3)
                    .padding(.trailing, 6)
            }
            if AppGraph.shared.ui.isStarred(song) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(c.accent)
                    .padding(.trailing, 6)
            }
            if let duration = song.duration {
                Text(Format.time(Double(duration)))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(c.ink3)
            }
            if selecting {
                Spacer().frame(width: 12)
            } else {
                SongMenuButton(song: song, downloaded: downloaded, extra: extra)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .padding(.vertical, compact ? 4 : 7)
        .background(selected ? c.accentSoft : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .animation(theme.ease, value: selecting)

        if selecting {
            row
        } else {
            row.contextMenu {
                if let onSelect {
                    Button(action: onSelect) { Label("Select", systemImage: "checkmark.circle") }
                    Divider()
                }
                SongMenuItems(song: song, downloaded: downloaded, extra: extra)
            }
        }
    }
}

/**
 * Track rows for a list. Tapping plays the list from that track (or toggles
 * selection while selecting); long-press opens its menu, swipe to queue it.
 */
struct SongRows: View {
    @Environment(\.kultr) private var theme
    let songs: [Song]
    var selection: SongSelection?
    var numbered = false
    var showArtwork = true
    var keyPrefix = "song"
    var extra: (Int, Song) -> [MenuAction] = { _, _ in [] }
    let onPlay: (Int) -> Void

    var body: some View {
        let player = AppGraph.shared.player.state
        let downloaded = AppGraph.shared.offline.downloadedIds
        let compact = AppGraph.shared.settings.settings.compactRows
        let selecting = selection?.active == true
        ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
            SongRow(
                song: song,
                number: numbered ? (song.track ?? index + 1) : nil,
                showArtwork: showArtwork,
                isCurrent: song.id == player.current?.id,
                downloaded: downloaded.contains(song.id),
                selected: selecting && selection?.contains(song.id) == true,
                selecting: selecting,
                compact: compact,
                extra: extra(index, song),
                onTap: {
                    if let selection, selection.active {
                        selection.toggle(song.id)
                    } else {
                        onPlay(index)
                    }
                },
                onSelect: selection.map { sel -> () -> Void in { sel.toggle(song.id) } }
            )
            .id("\(keyPrefix):\(index):\(song.id)")
            // Inside a List: edge to edge, no separators, and swipe to queue.
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    AppGraph.shared.actions.playNext([song])
                } label: {
                    Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                .tint(theme.colors.accent)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button {
                    AppGraph.shared.actions.enqueue([song])
                } label: {
                    Label("Add to queue", systemImage: "text.line.last.and.arrowtriangle.forward")
                }
                .tint(.indigo)
            }
        }
    }
}

/** The bar shown while tracks are selected. */
struct SelectionBar: View {
    @Environment(\.kultr) private var theme
    let selection: SongSelection
    let songs: [Song]

    var body: some View {
        ZStack {
            if selection.active {
                bar.transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(theme.spring, value: selection.active)
    }

    private var bar: some View {
        let actions = AppGraph.shared.actions
        let picked = selection.picked(songs)
        return GlassGroup {
            HStack(spacing: 2) {
                iconButton("xmark", "Clear selection") { selection.clear() }
                Text("\(picked.count) selected")
                    .font(KFont.titleSmall)
                    .foregroundStyle(theme.colors.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                iconButton("play.fill", "Play") { actions.play(picked); selection.clear() }
                iconButton("text.line.first.and.arrowtriangle.forward", "Play next") { actions.playNext(picked); selection.clear() }
                iconButton("music.note.list", "Add to queue") { actions.enqueue(picked); selection.clear() }
                Menu {
                    Button("Select all") { selection.selectAll(songs) }
                    Button { actions.addToPlaylist(picked); selection.clear() } label: { Label("Add to playlist…", systemImage: "text.badge.plus") }
                    Button { actions.setFavourite(picked, true); selection.clear() } label: { Label("Add to favourites", systemImage: "heart.fill") }
                    Button { actions.setFavourite(picked, false); selection.clear() } label: { Label("Remove from favourites", systemImage: "heart") }
                    Button { actions.download(picked); selection.clear() } label: { Label("Download", systemImage: "arrow.down.circle") }
                    Button(role: .destructive) { actions.removeDownloads(picked); selection.clear() } label: { Label("Remove downloads", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(theme.colors.ink)
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 4)
            .kultrGlass(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func iconButton(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.colors.ink)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }
}

/** A round icon button, like Material's IconButton. */
struct IconButton: View {
    @Environment(\.kultr) private var theme
    let icon: String
    var tint: Color?
    var size: CGFloat = 20
    var label = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint ?? theme.colors.ink)
                .frame(width: max(44, size * 1.8), height: max(44, size * 1.8))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}
