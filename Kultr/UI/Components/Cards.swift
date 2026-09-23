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
        .dragSource({
            let album = album
            return DragPayload(label: album.name, coverId: album.coverArt ?? album.id) {
                await AppGraph.shared.library.songsOfAlbumNow(album.id)
            }
        })
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
        .dragSource({
            let artist = artist
            return DragPayload(label: artist.name, coverId: artist.coverArt) {
                await AppGraph.shared.actions.artistSongs(artist)
            }
        })
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
        .dragSource({
            let playlist = playlist
            return DragPayload(label: playlist.name, coverId: playlist.coverArt) {
                await AppGraph.shared.actions.playlistSongs(playlist)
            }
        })
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
        .buttonStyle(PressableStyle())
    }
}
