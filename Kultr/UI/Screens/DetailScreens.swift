import SwiftUI

/** A back arrow that floats over the header. */
struct BackBar: View {
    @Environment(\.kultr) private var theme
    var title: String?

    var body: some View {
        HStack(spacing: 0) {
            IconButton(icon: "chevron.backward", tint: theme.colors.ink, size: 22, label: "Back") { AppGraph.shared.actions.back() }
            if let title {
                Text(title).font(KFont.titleMedium).foregroundStyle(theme.colors.ink).lineLimit(1)
            }
            Spacer()
        }
        .padding(4)
    }
}

/** Artwork, eyebrow, title, subtitle and actions — the top of every detail page. */
struct DetailHeader<Subtitle: View, Actions: View>: View {
    @Environment(\.kultr) private var theme
    let eyebrow: String
    let title: String
    let coverId: String?
    var circle = false
    var imageUrl: URL?
    var tags: [(String, (() -> Void)?)] = []
    @ViewBuilder let subtitle: () -> Subtitle
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        let c = theme.colors
        VStack(alignment: .leading, spacing: 0) {
            ArtworkFill(coverId: coverId, circle: circle, radius: theme.radii.lg, label: title, pixels: 600, imageUrl: imageUrl)
                .frame(width: 220, height: 220)
                .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
                .frame(maxWidth: .infinity)
            Spacer().frame(height: 18)
            Eyebrow(eyebrow)
            Text(title)
                .font(KFont.headlineMedium)
                .foregroundStyle(c.ink)
                .lineLimit(3)
            Spacer().frame(height: 4)
            subtitle()
            if !tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in Tag(tag.0, action: tag.1) }
                }
                .padding(.top, 8)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { actions() }
                    .padding(.horizontal, 20)
            }
            .padding(.horizontal, -20)
            .padding(.top, 14)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
    }
}

struct DownloadPill: View {
    let songs: [Song]
    let label: String

    var body: some View {
        let graph = AppGraph.shared
        let downloaded = graph.offline.downloadedIds
        let missing = songs.filter { !$0.isRadio && !downloaded.contains($0.id) }.count
        if !songs.isEmpty {
            if missing == 0 {
                Pill("Remove download", icon: "checkmark.circle.fill") { graph.actions.removeDownloads(songs) }
            } else {
                Pill("Download", icon: "arrow.down.circle", badge: "\(missing)") { graph.actions.download(songs, label) }
            }
        }
    }
}

private struct DetailScaffold<Content: View>: View {
    let selection: SongSelection
    let songs: [Song]
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .top) {
            AccentWash()
            VStack(spacing: 0) {
                BackBar()
                if selection.active { SelectionBar(selection: selection, songs: songs) }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) { content() }
                        .padding(.bottom, 24)
                }
            }
        }
        .kultrScreen()
    }
}

private struct DetailLoading: View {
    var body: some View {
        VStack(spacing: 0) {
            BackBar()
            LoadingView()
        }
        .kultrScreen()
    }
}

/** Last.fm biographies arrive with a trailing link; keep the words. */
func cleanHtml(_ text: String) -> String {
    text
        .replacingOccurrences(of: "<a [^>]*>.*?</a>\\.?", with: "", options: .regularExpression)
        .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

// ---------------------------------------------------------------- album --

struct AlbumScreen: View {
    @Environment(\.kultr) private var theme
    let id: String
    @State private var album: Album?
    @State private var songs: [Song] = []
    @State private var loaded = false
    @State private var notes: String?
    @State private var selection = SongSelection()

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        Group {
            if let shown = album {
                let discs = Dictionary(grouping: songs) { $0.discNumber ?? 1 }.sorted { $0.key < $1.key }
                DetailScaffold(selection: selection, songs: songs) {
                    DetailHeader(
                        eyebrow: shown.isCompilation == true ? "Compilation" : "Album",
                        title: shown.name,
                        coverId: shown.coverArt ?? shown.id,
                        tags: genreTags(shown.genre)
                    ) {
                        HStack(spacing: 0) {
                            Text(shown.artist ?? "")
                                .font(KFont.bodyLarge)
                                .foregroundStyle(c.ink)
                                .lineLimit(1)
                                .onTapGesture { graph.actions.openArtist(shown.artistId) }
                            Text(
                                " · " + [
                                    shown.year.map { String($0) },
                                    Format.count(songs.count, "track"),
                                    Format.duration(Int64(shown.duration ?? songs.reduce(0) { $0 + ($1.duration ?? 0) })),
                                ].compactMap { $0 }.joined(separator: " · ")
                            )
                            .font(KFont.bodyMedium)
                            .foregroundStyle(c.ink2)
                            .lineLimit(1)
                        }
                    } actions: {
                        Pill("Play", icon: "play.fill", accent: true) { graph.actions.play(songs) }
                        Pill("Shuffle", icon: "shuffle") { graph.actions.shuffle(songs) }
                        Pill("Favourite", icon: shown.isStarred ? "heart.fill" : "heart") {
                            graph.actions.setAlbumFavourite(shown, !shown.isStarred)
                            album?.starred = shown.isStarred ? nil : "now"
                        }
                        Pill("Queue", icon: "text.line.last.and.arrowtriangle.forward") { graph.actions.enqueue(songs) }
                        Pill("Add to playlist", icon: "text.badge.plus") { graph.actions.addToPlaylist(songs) }
                        DownloadPill(songs: songs, label: shown.name)
                    }
                    if songs.isEmpty { LoadingView() }
                    ForEach(discs, id: \.key) { entry in
                        let disc = entry.key
                        let discSongs = entry.value
                        if discs.count > 1 { SectionHeader("Disc \(disc)") }
                        SongRows(songs: discSongs, selection: selection, numbered: true, showArtwork: false, keyPrefix: "disc\(disc)") { index in
                            let target = songs.firstIndex(of: discSongs[index]) ?? 0
                            graph.actions.play(songs, target)
                        }
                    }
                    if let notes {
                        let text = cleanHtml(notes)
                        if !text.isEmpty {
                            SectionHeader("About this album")
                            Text(text)
                                .font(KFont.bodyMedium)
                                .foregroundStyle(c.ink2)
                                .padding(.horizontal, 16)
                        }
                    }
                }
            } else if loaded {
                VStack(spacing: 0) {
                    BackBar()
                    EmptyState(icon: "opticaldisc", title: "Album not found", message: "It may have been removed from your server.")
                }
                .kultrScreen()
            } else {
                DetailLoading()
            }
        }
        .task(id: "\(id):\(graph.library.version)") { await load() }
        .task(id: id) { notes = await graph.library.albumNotes(id) }
    }

    private func genreTags(_ genre: String?) -> [(String, (() -> Void)?)] {
        guard let genre, !genre.isEmpty else { return [] }
        let open: () -> Void = { AppGraph.shared.actions.openGenre(genre) }
        return [(genre, open)]
    }

    private func load() async {
        let graph = AppGraph.shared
        let local = await graph.library.album(id)
        let localSongs = await graph.library.songsOfAlbum(id)
        if local != nil && !localSongs.isEmpty {
            album = local
            songs = localSongs
        } else {
            // Albums the mirror does not have (not synced yet) come straight from the server.
            let remote = try? await graph.auth.client?.getAlbum(id)
            album = local ?? remote
            songs = localSongs.isEmpty ? (remote?.song ?? []) : localSongs
        }
        loaded = true
    }
}

// --------------------------------------------------------------- artist --

struct ArtistScreen: View {
    @Environment(\.kultr) private var theme
    let id: String
    @State private var artist: Artist?
    @State private var remote: Artist?
    @State private var albums: [Album] = []
    @State private var songs: [Song] = []
    @State private var info: ArtistInfo?
    @State private var top: [Song] = []
    @State private var loaded = false
    @State private var bioOpen = false
    @State private var selection = SongSelection()

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        Group {
            if let shown = artist ?? remote {
                let allAlbums = albums.isEmpty ? (remote?.album ?? []) : albums
                let popular = Array((top.isEmpty ? songs.sorted { ($0.playCount ?? 0) > ($1.playCount ?? 0) } : top).prefix(10))
                let imageUrl = shown.coverArt == nil ? info?.largeImageUrl.flatMap { $0.hasPrefix("http") ? URL(string: $0) : nil } : nil
                DetailScaffold(selection: selection, songs: popular) {
                    DetailHeader(eyebrow: "Artist", title: shown.name, coverId: shown.coverArt, circle: true, imageUrl: imageUrl) {
                        Text([Format.count(allAlbums.count, "album"), songs.isEmpty ? nil : Format.count(songs.count, "track")].compactMap { $0 }.joined(separator: " · "))
                            .font(KFont.bodyMedium)
                            .foregroundStyle(c.ink2)
                    } actions: {
                        Pill("Play", icon: "play.fill", accent: true) {
                            Task { graph.actions.play(await graph.actions.artistSongs(shown)) }
                        }
                        Pill("Shuffle", icon: "shuffle") {
                            Task { graph.actions.shuffle(await graph.actions.artistSongs(shown)) }
                        }
                        Pill("Favourite", icon: shown.isStarred ? "heart.fill" : "heart") {
                            graph.actions.setArtistFavourite(shown, !shown.isStarred)
                            if artist != nil {
                                artist?.starred = shown.isStarred ? nil : "now"
                            } else {
                                remote?.starred = shown.isStarred ? nil : "now"
                            }
                        }
                        Pill("InjeKt radio", icon: "sparkles") {
                            Task {
                                let pool = songs.isEmpty ? await graph.actions.artistSongs(shown) : songs
                                if let seed = pool.randomElement() { graph.actions.startInjektSet(seed) }
                            }
                        }
                        DownloadPill(songs: songs, label: shown.name)
                    }
                    if !popular.isEmpty {
                        SectionHeader("Popular")
                        SongRows(songs: popular, selection: selection, keyPrefix: "top") { graph.actions.play(popular, $0) }
                    }
                    if !allAlbums.isEmpty {
                        SectionHeader("Albums")
                        Shelf(items: allAlbums) { AlbumCard(album: $0) }
                    }
                    if let similar = info?.similarArtist, !similar.isEmpty {
                        SectionHeader("Similar artists")
                        Shelf(items: similar, cardWidth: 130) { ArtistCard(artist: $0) }
                    }
                    if let bio = info?.biography {
                        let text = cleanHtml(bio)
                        if !text.isEmpty {
                            SectionHeader("About")
                            Text(text)
                                .font(KFont.bodyMedium)
                                .foregroundStyle(c.ink2)
                                .lineLimit(bioOpen ? nil : 5)
                                .padding(.horizontal, 16)
                                .contentShape(Rectangle())
                                .onTapGesture { withAnimation { bioOpen.toggle() } }
                        }
                    }
                }
            } else if loaded {
                VStack(spacing: 0) {
                    BackBar()
                    EmptyState(icon: "person.fill", title: "Artist not found", message: "It may have been removed from your server.")
                }
                .kultrScreen()
            } else {
                DetailLoading()
            }
        }
        .task(id: "\(id):\(graph.library.version)") {
            artist = await graph.library.artist(id)
            albums = await graph.library.albumsOfArtist(id)
            songs = await graph.library.songsOfArtist(id)
            if artist == nil || albums.isEmpty, remote == nil {
                remote = try? await graph.auth.client?.getArtist(id)
            }
            loaded = true
        }
        .task(id: id) {
            info = await graph.library.artistInfo(id)
        }
        .task(id: (artist ?? remote)?.name ?? "") {
            if let name = (artist ?? remote)?.name { top = await graph.library.topSongs(name) }
        }
    }
}

// ------------------------------------------------------------- playlist --

struct PlaylistScreen: View {
    @Environment(\.kultr) private var theme
    let id: String
    @State private var detail: PlaylistDetail?
    @State private var loaded = false
    @State private var refreshedOnce = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var deleting = false
    @State private var selection = SongSelection()

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        Group {
            if let d = detail {
                let songs = d.songs
                let username = graph.auth.active?.username
                let editable = d.playlist.owner == nil || d.playlist.owner == username
                DetailScaffold(selection: selection, songs: songs) {
                    DetailHeader(eyebrow: d.playlist.isPublic == true ? "Public playlist" : "Playlist", title: d.playlist.name, coverId: d.playlist.coverArt) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(
                                [
                                    d.playlist.owner.map { "by \($0)" },
                                    Format.count(songs.count, "track"),
                                    Format.duration(Int64(songs.reduce(0) { $0 + ($1.duration ?? 0) })),
                                ].compactMap { $0 }.joined(separator: " · ")
                            )
                            .font(KFont.bodyMedium)
                            .foregroundStyle(c.ink2)
                            if let comment = d.playlist.comment, !comment.trimmingCharacters(in: .whitespaces).isEmpty {
                                Text(comment).font(KFont.bodySmall).foregroundStyle(c.ink3)
                            }
                        }
                    } actions: {
                        Pill("Play", icon: "play.fill", accent: true) { graph.actions.play(songs) }
                        Pill("Shuffle", icon: "shuffle") { graph.actions.shuffle(songs) }
                        Pill("Queue", icon: "text.line.last.and.arrowtriangle.forward") { graph.actions.enqueue(songs) }
                        DownloadPill(songs: songs, label: d.playlist.name)
                        if editable {
                            Pill("Rename", icon: "pencil") {
                                newName = d.playlist.name
                                renaming = true
                            }
                            Pill("Delete", icon: "trash") { deleting = true }
                        }
                    }
                    if songs.isEmpty {
                        EmptyState(icon: "music.note.list", title: "This playlist is empty", message: "Add tracks from any track's menu.")
                    }
                    SongRows(
                        songs: songs,
                        selection: selection,
                        extra: { index, _ in
                            guard editable else { return [] }
                            return [
                                MenuAction(label: "Remove from this playlist", icon: "minus.circle") {
                                    Task {
                                        if let error = await graph.library.removeFromPlaylist(id, [index]) { graph.messages.error(error) }
                                    }
                                },
                            ]
                        }
                    ) { graph.actions.play(songs, $0) }
                }
                .alert("Rename playlist", isPresented: $renaming) {
                    TextField("Name", text: $newName)
                    Button("Cancel", role: .cancel) {}
                    Button("Rename") {
                        let name = newName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        Task { if let error = await graph.library.renamePlaylist(id, name) { graph.messages.error(error) } }
                    }
                }
                .alert("Delete “\(d.playlist.name)”?", isPresented: $deleting) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) {
                        Task {
                            if let error = await graph.library.deletePlaylist(id) {
                                graph.messages.error(error)
                            } else {
                                graph.actions.back()
                            }
                        }
                    }
                } message: {
                    Text("The playlist is deleted on your server. The tracks in it are not affected.")
                }
            } else if loaded {
                VStack(spacing: 0) {
                    BackBar()
                    EmptyState(icon: "music.note.list", title: "Playlist not found", message: "It may have been deleted on the server.")
                }
                .kultrScreen()
            } else {
                DetailLoading()
            }
        }
        .task(id: "\(id):\(graph.library.version)") {
            detail = await graph.library.playlist(id)
            loaded = true
            // Contents may not have been synced; fetch them once if the list looks short.
            if let d = detail, !refreshedOnce, d.songs.count < (d.playlist.songCount ?? 0) {
                refreshedOnce = true
                _ = await graph.library.refreshPlaylist(id)
            }
            if detail == nil && !refreshedOnce {
                refreshedOnce = true
                _ = await graph.library.refreshPlaylist(id)
            }
        }
    }
}

// ---------------------------------------------------------------- genre --

struct GenreScreen: View {
    @Environment(\.kultr) private var theme
    let name: String
    @State private var songs: [Song] = []
    @State private var albums: [Album] = []
    @State private var selection = SongSelection()

    var body: some View {
        let graph = AppGraph.shared
        DetailScaffold(selection: selection, songs: songs) {
            DetailHeader(eyebrow: "Genre", title: name, coverId: nil) {
                Text("\(Format.count(albums.count, "album")) · \(Format.count(songs.count, "track"))")
                    .font(KFont.bodyMedium)
                    .foregroundStyle(theme.colors.ink2)
            } actions: {
                Pill("Shuffle", icon: "shuffle", accent: true) { graph.actions.shuffle(songs) }
                Pill("InjeKt set", icon: "sparkles") {
                    if let seed = songs.randomElement() { graph.actions.startInjektSet(seed) }
                }
                DownloadPill(songs: songs, label: name)
            }
            if !albums.isEmpty {
                SectionHeader("Albums")
                Shelf(items: albums) { AlbumCard(album: $0) }
            }
            if !songs.isEmpty {
                SectionHeader("Tracks")
                SongRows(songs: songs, selection: selection) { graph.actions.playWindow(songs, $0) }
            }
        }
        .task(id: "\(name):\(graph.library.version)") {
            songs = await graph.library.songsOfGenre(name)
            albums = await graph.library.albumsOfGenre(name)
        }
    }
}
