import SwiftUI

private func tileIcon(_ id: String) -> String {
    if id == "recentlyPlayed" { return "clock.arrow.circlepath" }
    if id.hasPrefix("mostPlayed") { return "play.fill" }
    if id.hasPrefix("random") { return "shuffle" }
    if id == "recentlyAdded" { return "opticaldisc" }
    if id == "favouritePlaylists" { return "music.note.list" }
    if id.hasPrefix("favourite") { return "heart.fill" }
    return "radio"
}

struct HomeScreen: View {
    @Environment(\.kultr) private var theme
    @State private var counts = LibraryCounts()
    @State private var syncState = SyncState()
    @State private var loaded = false
    @State private var hour = Calendar.current.component(.hour, from: Date())

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        let sync = graph.sync
        let tiles = resolveHomeTiles(theme.settings.homeTiles)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        Text(Format.greeting(hour))
                            .font(KFont.headlineMedium)
                            .tracking(-0.3)
                            .foregroundStyle(c.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        CastButton()
                        IconButton(icon: "chart.bar.fill", tint: c.ink2, label: "Listening stats") { graph.actions.navigate(.stats) }
                        IconButton(icon: "arrow.triangle.2.circlepath", tint: sync.running ? c.accent : c.ink2, label: "Sync") {
                            graph.actions.navigate(.sync)
                        }
                    }
                    Text(
                        sync.running
                            ? (sync.progress?.message ?? "Syncing…")
                            : "\(Format.count(counts.songs, "track")) · \(Format.count(counts.albums, "album")) · checked \(Format.relative(syncState.lastCheck))"
                    )
                    .font(KFont.bodySmall)
                    .foregroundStyle(c.ink3)
                    .lineLimit(1)
                    if counts.songs > 0 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Pill("Shuffle all", icon: "shuffle") {
                                    Task { graph.actions.shuffle(await graph.library.randomSongs(200)) }
                                }
                                Pill("Start an InjeKt set", icon: "sparkles", accent: true) { graph.actions.startInjektSet() }
                            }
                        }
                        .padding(.top, 14)
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 4)
                .padding(.top, 12)
                .padding(.bottom, 8)

                if loaded && counts.albums == 0 {
                    EmptyState(
                        icon: "opticaldisc",
                        title: sync.running ? "Syncing your library…" : "Your library is not synced yet",
                        message: "Kultr keeps a copy of your library on this phone, so browsing is instant and works without a connection. It is a one-time job — after that, only changes are fetched."
                    ) {
                        Pill(sync.running ? "Syncing…" : "Sync my library", icon: "arrow.triangle.2.circlepath", accent: true, enabled: !sync.running) {
                            sync.start(.full)
                        }
                    }
                } else if loaded {
                    ForEach(tiles) { tile in
                        HomeShelf(tile: tile, counts: counts, lastCheck: syncState.lastCheck)
                    }
                    if tiles.isEmpty {
                        EmptyState(
                            icon: "heart.fill",
                            title: "Nothing on the home page yet",
                            message: "Choose what appears here, and in what order, in Settings → Home page."
                        )
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .kultrScreen()
        .task(id: graph.library.version) {
            counts = await graph.library.counts()
            syncState = await graph.library.syncState()
            loaded = true
        }
        .onAppear { hour = Calendar.current.component(.hour, from: Date()) }
    }
}

private struct HomeShelf: View {
    @Environment(\.kultr) private var theme
    let tile: HomeTile
    let counts: LibraryCounts
    let lastCheck: Int64?

    @State private var songs: [Song] = []
    @State private var albums: [Album] = []
    @State private var artists: [Artist] = []
    @State private var playlists: [Playlist] = []
    @State private var stations: [RadioStation] = []

    private var seeAllTab: LibraryTab? {
        switch tile.id {
        case "mostPlayedAlbums", "recentlyAdded", "randomAlbums": return .albums
        case "mostPlayedArtists", "randomArtists": return .artists
        case "favouriteSongs", "favouriteAlbums", "favouriteArtists": return .favourites
        case "mostPlayedPlaylists", "favouritePlaylists": return .playlists
        case "radios", "favouriteRadios": return .radio
        case "mostPlayedSongs": return .songs
        default: return nil
        }
    }

    /** What makes this shelf reload: the library, and for some the track playing. */
    private var reloadKey: String {
        let graph = AppGraph.shared
        // A random shelf only reshuffles when the library itself grows or shrinks.
        var key = tile.id.hasPrefix("random")
            ? "\(tile.id):\(counts.songs):\(counts.albums):\(counts.artists):\(lastCheck ?? 0)"
            : "\(tile.id):\(graph.library.version):\(lastCheck ?? 0)"
        if tile.id == "recentlyPlayed" { key += ":\(graph.player.state.current?.id ?? ""):\(graph.library.historyVersion)" }
        if tile.id == "favouriteRadios" { key += ":\(theme.settings.favouriteRadios.joined(separator: ","))" }
        return key
    }

    var body: some View {
        let graph = AppGraph.shared
        let playing = graph.player.state.current?.id
        let downloaded = graph.offline.downloadedIds
        Group {
            switch tile.kind {
            case .songs:
                if !songs.isEmpty {
                    header
                    VStack(spacing: 0) {
                        ForEach(Array(songs.prefix(10).enumerated()), id: \.offset) { index, song in
                            SongRow(
                                song: song,
                                isCurrent: song.id == playing,
                                downloaded: downloaded.contains(song.id),
                                compact: theme.settings.compactRows,
                                dragPayload: { DragPayload(label: song.title, coverId: song.artworkId) { [song] } },
                                onTap: { graph.actions.play(Array(songs.prefix(10)), index) }
                            )
                        }
                    }
                }
            case .albums:
                if !albums.isEmpty {
                    header
                    Shelf(items: Array(albums.prefix(16))) { AlbumCard(album: $0) }
                }
            case .artists:
                if !artists.isEmpty {
                    header
                    Shelf(items: Array(artists.prefix(16)), cardWidth: 130) { ArtistCard(artist: $0) }
                }
            case .playlists:
                if !playlists.isEmpty {
                    header
                    Shelf(items: Array(playlists.prefix(16))) { PlaylistCard(playlist: $0) }
                }
            case .radios:
                if !stations.isEmpty {
                    header
                    Shelf(items: stations, cardWidth: 130) { StationCard(station: $0) }
                }
            }
        }
        .task(id: reloadKey) { await load() }
    }

    private var header: some View {
        SectionHeader(tile.title, icon: tileIcon(tile.id)) {
            if let tab = seeAllTab {
                Pill("See all") { AppGraph.shared.actions.openLibrary(tab) }
            }
        }
        .padding(.top, 12)
    }

    private func load() async {
        let graph = AppGraph.shared
        let library = graph.library
        switch tile.id {
        case "mostPlayedSongs": songs = await library.mostPlayedSongs(10)
        case "favouriteSongs": songs = await library.starredSongs()
        case "recentlyPlayed": songs = await library.recentlyPlayed(10)
        case "randomSongs": songs = await library.randomSongs(10)
        case "mostPlayedAlbums": albums = await library.mostPlayedAlbums(16)
        case "recentlyAdded": albums = await library.recentlyAdded(16)
        case "favouriteAlbums": albums = await library.starredAlbums()
        case "randomAlbums": albums = await library.randomAlbums(16)
        case "mostPlayedArtists": artists = await library.mostPlayedArtists(16)
        case "favouriteArtists": artists = await library.starredArtists()
        case "randomArtists": artists = await library.randomArtists(16)
        case "mostPlayedPlaylists": playlists = await library.playlistsByPlays()
        case "favouritePlaylists":
            let username = graph.auth.active?.username
            playlists = await library.playlists()
                .filter { $0.owner == nil || $0.owner == username }
                .sorted { ($0.changed ?? $0.created ?? "") > ($1.changed ?? $1.created ?? "") }
        case "radios", "favouriteRadios":
            let all = (try? await library.radioStations()) ?? []
            let favourites = theme.settings.favouriteRadios
            stations = tile.id == "favouriteRadios" ? all.filter { favourites.contains($0.id) } : all
        default:
            break
        }
    }
}
