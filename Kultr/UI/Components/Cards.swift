import SwiftUI

extension GridSize {
    var minCell: CGFloat {
        switch self {
        case .small: return 104
        case .medium: return 144
        case .large: return 190
        }
    }
}

struct AlbumCard: View {
    @Environment(\.kultr) private var theme
    let album: Album

    var body: some View {
        let sub = [album.artist, album.year.map(String.init)].compactMap { $0 }.joined(separator: " · ")
        VStack(alignment: .leading, spacing: 0) {
            ArtworkFill(coverId: album.coverArt ?? album.id, label: album.name)
            Spacer().frame(height: 8)
            Text(album.name)
                .font(KFont.bodyMedium.weight(.semibold))
                .foregroundStyle(theme.colors.ink)
                .lineLimit(1)
            Text(sub)
                .font(KFont.bodySmall)
                .foregroundStyle(theme.colors.ink3)
                .lineLimit(1)
        }
        .padding(6)
        .contentShape(Rectangle())
        .onTapGesture { AppGraph.shared.actions.openAlbum(album.id) }
        .contextMenu {
            CollectionMenuItems(name: album.name) { await AppGraph.shared.library.songsOfAlbumNow(album.id) }
            Divider()
            let starred = AppGraph.shared.ui.isStarred(album)
            Button { AppGraph.shared.actions.setAlbumFavourite(album, !starred) } label: {
                Label(starred ? "Remove from favourites" : "Add to favourites", systemImage: starred ? "heart.slash" : "heart")
            }
            if album.artistId != nil {
                Button { AppGraph.shared.actions.openArtist(album.artistId) } label: { Label("Go to artist", systemImage: "person.fill") }
            }
        }
    }
}

struct ArtistCard: View {
    @Environment(\.kultr) private var theme
    let artist: Artist

    var body: some View {
        let external = artist.coverArt == nil && (artist.artistImageUrl ?? "").hasPrefix("http") ? URL(string: artist.artistImageUrl!) : nil
        VStack(spacing: 0) {
            ArtworkFill(coverId: artist.coverArt, circle: true, label: artist.name, imageUrl: external)
            Spacer().frame(height: 8)
            Text(artist.name)
                .font(KFont.bodyMedium.weight(.semibold))
                .foregroundStyle(theme.colors.ink)
                .lineLimit(1)
                .multilineTextAlignment(.center)
            if let count = artist.albumCount {
                Text(Format.count(count, "album"))
                    .font(KFont.bodySmall)
                    .foregroundStyle(theme.colors.ink3)
            }
        }
        .padding(6)
        .contentShape(Rectangle())
        .onTapGesture { AppGraph.shared.actions.openArtist(artist.id) }
        .contextMenu {
            CollectionMenuItems(name: artist.name) { await AppGraph.shared.actions.artistSongs(artist) }
            Divider()
            let starred = AppGraph.shared.ui.isStarred(artist)
            Button { AppGraph.shared.actions.setArtistFavourite(artist, !starred) } label: {
                Label(starred ? "Remove from favourites" : "Add to favourites", systemImage: starred ? "heart.slash" : "heart")
            }
        }
    }
}

struct PlaylistCard: View {
    @Environment(\.kultr) private var theme
    let playlist: Playlist

    var body: some View {
        let sub = [playlist.songCount.map { Format.count($0, "track") }, playlist.duration.map { Format.duration(Int64($0)) }]
            .compactMap { $0 }
            .joined(separator: " · ")
        VStack(alignment: .leading, spacing: 0) {
            ArtworkFill(coverId: playlist.coverArt, label: playlist.name)
            Spacer().frame(height: 8)
            Text(playlist.name)
                .font(KFont.bodyMedium.weight(.semibold))
                .foregroundStyle(theme.colors.ink)
                .lineLimit(1)
            Text(sub)
                .font(KFont.bodySmall)
                .foregroundStyle(theme.colors.ink3)
                .lineLimit(1)
        }
        .padding(6)
        .contentShape(Rectangle())
        .onTapGesture { AppGraph.shared.actions.openPlaylist(playlist.id) }
        .contextMenu {
            CollectionMenuItems(name: playlist.name) { await AppGraph.shared.actions.playlistSongs(playlist) }
        }
    }
}

struct StationCard: View {
    @Environment(\.kultr) private var theme
    let station: RadioStation

    var body: some View {
        Button {
            AppGraph.shared.actions.play([station.asSong()])
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ArtworkFill(coverId: nil, label: station.name)
                Spacer().frame(height: 8)
                Text(station.name)
                    .font(KFont.bodyMedium)
                    .foregroundStyle(theme.colors.ink)
                    .lineLimit(1)
                Text("Radio")
                    .font(KFont.bodySmall)
                    .foregroundStyle(theme.colors.ink3)
            }
            .padding(6)
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
        Button { run { actions.download($0, name) } } label: { Label("Download", systemImage: "arrow.down.circle") }
        Button(role: .destructive) { run { actions.removeDownloads($0) } } label: { Label("Remove downloads", systemImage: "trash") }
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
