import SwiftUI

extension GridSize {
    /** A card grid's columns: as many as fit at this size. */
    var columns: [GridItem] {
        let minimum: CGFloat = switch self {
        case .small: 104
        case .medium: 144
        case .large: 190
        }
        return [GridItem(.adaptive(minimum: minimum), spacing: 12, alignment: .top)]
    }
}

/** A grid card: artwork over a one-line title and subtitle. */
private struct CardLayout<Art: View>: View {
    @Environment(\.kultr) private var theme
    let title: String
    var subtitle: String?
    var alignment: HorizontalAlignment = .leading
    @ViewBuilder let art: Art

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            art
            Spacer().frame(height: 8)
            Text(title)
                .font(KFont.bodyMedium.weight(.semibold))
                .foregroundStyle(theme.colors.ink)
            if let subtitle {
                Text(subtitle)
                    .font(KFont.bodySmall)
                    .foregroundStyle(theme.colors.ink3)
            }
        }
        .lineLimit(1)
    }
}

struct AlbumCard: View {
    let album: Album

    var body: some View {
        let sub = [album.artist, album.year.map(String.init)].compactMap { $0 }.joined(separator: " · ")
        CardLayout(title: album.name, subtitle: sub) {
            ArtworkFill(coverId: album.coverArt ?? album.id, label: album.name)
        }
        .contentShape(Rectangle())
        .onTapGesture { AppGraph.shared.actions.openAlbum(album.id) }
        .contextMenu {
            CollectionMenuItems(name: album.name) { await AppGraph.shared.library.songsOfAlbumNow(album.id) }
            Divider()
            FavouriteMenuItem(starred: AppGraph.shared.ui.isStarred(album)) { AppGraph.shared.actions.setAlbumFavourite(album, $0) }
            if album.artistId != nil {
                Button { AppGraph.shared.actions.openArtist(album.artistId) } label: { Label("Go to artist", systemImage: "person.fill") }
            }
        }
    }
}

struct ArtistCard: View {
    let artist: Artist

    var body: some View {
        let external = artist.coverArt == nil && (artist.artistImageUrl ?? "").hasPrefix("http") ? URL(string: artist.artistImageUrl!) : nil
        CardLayout(title: artist.name, subtitle: artist.albumCount.map { Format.count($0, "album") }, alignment: .center) {
            ArtworkFill(coverId: artist.coverArt, circle: true, label: artist.name, imageUrl: external)
        }
        .contentShape(Rectangle())
        .onTapGesture { AppGraph.shared.actions.openArtist(artist.id) }
        .contextMenu {
            CollectionMenuItems(name: artist.name) { await AppGraph.shared.actions.artistSongs(artist) }
            Divider()
            FavouriteMenuItem(starred: AppGraph.shared.ui.isStarred(artist)) { AppGraph.shared.actions.setArtistFavourite(artist, $0) }
        }
    }
}

struct PlaylistCard: View {
    let playlist: Playlist

    var body: some View {
        let sub = [playlist.songCount.map { Format.count($0, "track") }, playlist.duration.map { Format.duration(Int64($0)) }]
            .compactMap { $0 }
            .joined(separator: " · ")
        CardLayout(title: playlist.name, subtitle: sub) {
            ArtworkFill(coverId: playlist.coverArt, label: playlist.name)
        }
        .contentShape(Rectangle())
        .onTapGesture { AppGraph.shared.actions.openPlaylist(playlist.id) }
        .contextMenu {
            CollectionMenuItems(name: playlist.name) { await AppGraph.shared.actions.playlistSongs(playlist) }
        }
    }
}

/** A long-press menu's favourite toggle; [set] gets the new state. */
private struct FavouriteMenuItem: View {
    let starred: Bool
    let set: (Bool) -> Void

    var body: some View {
        Button { set(!starred) } label: {
            Label(starred ? "Remove from favourites" : "Add to favourites", systemImage: starred ? "heart.slash" : "heart")
        }
    }
}

struct StationCard: View {
    let station: RadioStation

    var body: some View {
        Button {
            AppGraph.shared.actions.play([station.asSong()])
        } label: {
            CardLayout(title: station.name, subtitle: "Radio") {
                ArtworkFill(coverId: nil, label: station.name)
            }
        }
        .buttonStyle(PressScaleStyle())
    }
}

/**
 * The long-press menu of an album, artist or playlist: what the web and
 * Android apps offer as drop targets, in iOS's own menu. [songs] is only
 * called when an entry is chosen, so opening the menu loads nothing.
 */
struct CollectionMenuItems: View {
    let name: String
    let songs: @MainActor () async -> [Song]

    var body: some View {
        let actions = AppGraph.shared.actions
        Button { run { actions.play($0) } } label: { Label("Play", systemImage: "play.fill") }
        Button { run { actions.shuffle($0) } } label: { Label("Shuffle", systemImage: "shuffle") }
        Button { run { actions.playNext($0) } } label: { Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") }
        Button { run { actions.enqueue($0) } } label: { Label("Add to queue", systemImage: "text.line.last.and.arrowtriangle.forward") }
        Button { run { actions.addToPlaylist($0) } } label: { Label("Add to playlist…", systemImage: "text.badge.plus") }
        if !AppGraph.shared.isLocal {
            Button { run { actions.download($0, name) } } label: { Label("Download", systemImage: "arrow.down.circle") }
            Button(role: .destructive) { run { actions.removeDownloads($0) } } label: { Label("Remove downloads", systemImage: "trash") }
        }
    }

    private func run(_ body: @escaping @MainActor ([Song]) -> Void) {
        let songs = self.songs
        let name = self.name
        Task { @MainActor in
            let list = await songs().filter { !$0.isRadio }
            if list.isEmpty {
                AppGraph.shared.messages.show("“\(name)” has no tracks here yet.")
            } else {
                body(list)
            }
        }
    }
}
