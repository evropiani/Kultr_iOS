import SwiftUI

/** Whether a detail page's title has scrolled up under the navigation bar. */
private struct HeaderGoneKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/**
 * The top of every detail page: large artwork, the title and what it is,
 * then Play and Shuffle side by side, as in Apple Music. [subtitle] sits
 * under the title.
 */
struct DetailHeader<Subtitle: View>: View {
    @Environment(\.kultr) private var theme
    let eyebrow: String
    let title: String
    let coverId: String?
    var circle = false
    var imageUrl: URL?
    var play: (() -> Void)?
    var shuffle: (() -> Void)?
    @ViewBuilder let subtitle: () -> Subtitle

    var body: some View {
        let c = theme.colors
        VStack(spacing: 0) {
            ArtworkFill(coverId: coverId, circle: circle, radius: circle ? nil : 14, label: title, pixels: 800, imageUrl: imageUrl)
                .frame(width: 250, height: 250)
                .shadow(color: .black.opacity(c.dark ? 0.45 : 0.22), radius: 26, y: 14)
                .padding(.top, 8)
            Text(eyebrow.uppercased())
                .font(KFont.eyebrow)
                .tracking(1.4)
                .foregroundStyle(c.ink3)
                .padding(.top, 20)
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(c.ink)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.top, 4)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: HeaderGoneKey.self, value: proxy.frame(in: .global).maxY < 110)
                    }
                )
            subtitle()
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            if play != nil || shuffle != nil {
                GlassGroup(spacing: 12) {
                    HStack(spacing: 12) {
                        if let play { WideButton(title: "Play", icon: "play.fill", prominent: true, action: play) }
                        if let shuffle { WideButton(title: "Shuffle", icon: "shuffle", prominent: false, action: shuffle) }
                    }
                }
                .padding(.top, 18)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}

/** Play / Shuffle: half the width each, glass on iOS 26. */
private struct WideButton: View {
    @Environment(\.kultr) private var theme
    let title: String
    let icon: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        let c = theme.colors
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Button {
            Haptics.tap()
            action()
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(prominent ? c.onAccent : c.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .contentShape(shape)
        }
        .buttonStyle(PressScaleStyle())
        .background(shape.fill(prominent && !Self.glassTints ? c.accent : .clear))
        .kultrGlass(shape, tint: prominent ? c.accent : nil, interactive: true, shadow: false)
    }

    /** On iOS 26 the glass itself carries the accent; before, the button is filled with it. */
    private static var glassTints: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }
}

/**
 * A detail page: a scrolling column under iOS's navigation bar, whose title
 * appears once the header's title has scrolled under it, with the page's
 * actions in the bar.
 */
private struct DetailScaffold<Content: View, Actions: View>: View {
    @Environment(\.kultr) private var theme
    let title: String
    let selection: SongSelection
    let songs: [Song]
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions
    @State private var titleShown = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) { content() }
                .padding(.bottom, 32)
        }
        .onPreferenceChange(HeaderGoneKey.self) { gone in
            if gone != titleShown { withAnimation(theme.ease) { titleShown = gone } }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SelectionBar(selection: selection, songs: songs)
        }
        .background(alignment: .top) { AccentWash(height: 420) }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(theme.colors.ink)
                    .lineLimit(1)
                    .opacity(titleShown ? 1 : 0)
            }
            ToolbarItemGroup(placement: .topBarTrailing) { actions() }
        }
        .kultrScreen()
    }
}

private struct DetailMessage: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        EmptyState(icon: icon, title: title, message: message)
            .frame(maxHeight: .infinity)
            .kultrScreen()
    }
}

private struct DetailLoading: View {
    var body: some View {
        LoadingView()
            .frame(maxHeight: .infinity)
            .kultrScreen()
    }
}

/** Download everything here, or, once it is all on the phone, offer to remove it. */
struct DownloadToolbarButton: View {
    let songs: [Song]
    let label: String

    var body: some View {
        let graph = AppGraph.shared
        let downloaded = graph.offline.downloadedIds
        let missing = songs.filter { !$0.isRadio && !downloaded.contains($0.id) }.count
        if !songs.isEmpty {
            if missing == 0 {
                Menu {
                    Button(role: .destructive) { graph.actions.removeDownloads(songs) } label: {
                        Label("Remove download", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                }
                .accessibilityLabel("Downloaded")
            } else {
                Button { graph.actions.download(songs, label) } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .accessibilityLabel("Download \(missing) tracks")
            }
        }
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

/** A paragraph of notes or biography that opens up when tapped. */
private struct AboutText: View {
    @Environment(\.kultr) private var theme
    let title: String
    let text: String
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title)
            Text(text)
                .font(KFont.bodyMedium)
                .foregroundStyle(theme.colors.ink2)
                .lineLimit(open ? nil : 5)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(theme.ease) { open.toggle() } }
        }
    }
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
                let seconds = shown.duration ?? songs.reduce(0) { $0 + ($1.duration ?? 0) }
                DetailScaffold(title: shown.name, selection: selection, songs: songs) {
                    DetailHeader(
                        eyebrow: shown.isCompilation == true ? "Compilation" : "Album",
                        title: shown.name,
                        coverId: shown.coverArt ?? shown.id,
                        play: songs.isEmpty ? nil : { graph.actions.play(songs) },
                        shuffle: songs.isEmpty ? nil : { graph.actions.shuffle(songs) }
                    ) {
                        VStack(spacing: 3) {
                            if let artist = shown.artist {
                                Button { graph.actions.openArtist(shown.artistId) } label: {
                                    Text(artist)
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundStyle(c.accent)
                                        .lineLimit(1)
                                }
                                .buttonStyle(PressScaleStyle())
                                .disabled(shown.artistId == nil)
                            }
                            HStack(spacing: 4) {
                                if let genre = shown.genre, !genre.isEmpty {
                                    Button(genre) { graph.actions.openGenre(genre) }
                                        .buttonStyle(PressScaleStyle())
                                    Text("·")
                                }
                                Text(
                                    [shown.year.map { String($0) }, Format.count(songs.count, "track"), Format.duration(Int64(seconds))]
                                        .compactMap { $0 }
                                        .joined(separator: " · ")
                                )
                            }
                            .font(KFont.bodySmall.weight(.medium))
                            .foregroundStyle(c.ink3)
                        }
                    }
                    if songs.isEmpty { LoadingView() }
                    ForEach(discs, id: \.key) { entry in
                        let disc = entry.key
                        let discSongs = entry.value
                        if discs.count > 1 { SectionHeader("Disc \(disc)", icon: "opticaldisc") }
                        SongRows(songs: discSongs, selection: selection, numbered: true, showArtwork: false, keyPrefix: "disc\(disc)") { index in
                            let target = songs.firstIndex(of: discSongs[index]) ?? 0
                            graph.actions.play(songs, target)
                        }
                    }
                    if let notes {
                        let text = cleanHtml(notes)
                        if !text.isEmpty { AboutText(title: "About this album", text: text) }
                    }
                } actions: {
                    Button {
                        graph.actions.setAlbumFavourite(shown, !shown.isStarred)
                        album?.starred = shown.isStarred ? nil : "now"
                    } label: {
                        Image(systemName: shown.isStarred ? "heart.fill" : "heart")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .accessibilityLabel(shown.isStarred ? "Remove from favourites" : "Add to favourites")
                    DownloadToolbarButton(songs: songs, label: shown.name)
                    Menu {
                        Button { graph.actions.playNext(songs) } label: { Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") }
                        Button { graph.actions.enqueue(songs) } label: { Label("Add to queue", systemImage: "text.line.last.and.arrowtriangle.forward") }
                        Button { graph.actions.addToPlaylist(songs) } label: { Label("Add to playlist…", systemImage: "text.badge.plus") }
                        Button { graph.actions.startInjektSet(songs.randomElement()) } label: { Label("Start an InjeKt set", systemImage: "sparkles") }
                        if shown.artistId != nil {
                            Divider()
                            Button { graph.actions.openArtist(shown.artistId) } label: { Label("Go to artist", systemImage: "person.fill") }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More")
                }
            } else if loaded {
                DetailMessage(icon: "opticaldisc", title: "Album not found", message: "It may have been removed from your server.")
            } else {
                DetailLoading()
            }
        }
        .task(id: "\(id):\(graph.library.version)") { await load() }
        .task(id: id) { notes = await graph.library.albumNotes(id) }
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
    @State private var selection = SongSelection()

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        Group {
            if let shown = artist ?? remote {
                let allAlbums = albums.isEmpty ? (remote?.album ?? []) : albums
                let popular = Array((top.isEmpty ? songs.sorted { ($0.playCount ?? 0) > ($1.playCount ?? 0) } : top).prefix(10))
                let imageUrl = shown.coverArt == nil ? info?.largeImageUrl.flatMap { $0.hasPrefix("http") ? URL(string: $0) : nil } : nil
                DetailScaffold(title: shown.name, selection: selection, songs: popular) {
                    DetailHeader(
                        eyebrow: "Artist",
                        title: shown.name,
                        coverId: shown.coverArt,
                        circle: true,
                        imageUrl: imageUrl,
                        play: { Task { graph.actions.play(await graph.actions.artistSongs(shown)) } },
                        shuffle: { Task { graph.actions.shuffle(await graph.actions.artistSongs(shown)) } }
                    ) {
                        Text([Format.count(allAlbums.count, "album"), songs.isEmpty ? nil : Format.count(songs.count, "track")].compactMap { $0 }.joined(separator: " · "))
                            .font(KFont.bodySmall.weight(.medium))
                            .foregroundStyle(c.ink3)
                    }
                    if !popular.isEmpty {
                        SectionHeader("Popular", icon: "flame.fill")
                        SongRows(songs: popular, selection: selection, keyPrefix: "top") { graph.actions.play(popular, $0) }
                    }
                    if !allAlbums.isEmpty {
                        SectionHeader("Albums", icon: "square.stack.fill")
                        Shelf(items: allAlbums) { AlbumCard(album: $0) }
                    }
                    if let similar = info?.similarArtist, !similar.isEmpty {
                        SectionHeader("Similar artists", icon: "person.2.fill")
                        Shelf(items: similar, cardWidth: 130) { ArtistCard(artist: $0) }
                    }
                    if let bio = info?.biography {
                        let text = cleanHtml(bio)
                        if !text.isEmpty { AboutText(title: "About", text: text) }
                    }
                } actions: {
                    Button {
                        graph.actions.setArtistFavourite(shown, !shown.isStarred)
                        if artist != nil {
                            artist?.starred = shown.isStarred ? nil : "now"
                        } else {
                            remote?.starred = shown.isStarred ? nil : "now"
                        }
                    } label: {
                        Image(systemName: shown.isStarred ? "heart.fill" : "heart")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .accessibilityLabel(shown.isStarred ? "Remove from favourites" : "Add to favourites")
                    DownloadToolbarButton(songs: songs, label: shown.name)
                    Menu {
                        Button {
                            Task {
                                let pool = songs.isEmpty ? await graph.actions.artistSongs(shown) : songs
                                if let seed = pool.randomElement() { graph.actions.startInjektSet(seed) }
                            }
                        } label: {
                            Label("InjeKt radio", systemImage: "sparkles")
                        }
                        Button { Task { graph.actions.playNext(await graph.actions.artistSongs(shown)) } } label: {
                            Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward")
                        }
                        Button { Task { graph.actions.enqueue(await graph.actions.artistSongs(shown)) } } label: {
                            Label("Add to queue", systemImage: "text.line.last.and.arrowtriangle.forward")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More")
                }
            } else if loaded {
                DetailMessage(icon: "person.fill", title: "Artist not found", message: "It may have been removed from your server.")
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
                DetailScaffold(title: d.playlist.name, selection: selection, songs: songs) {
                    DetailHeader(
                        eyebrow: d.playlist.isPublic == true ? "Public playlist" : "Playlist",
                        title: d.playlist.name,
                        coverId: d.playlist.coverArt,
                        play: songs.isEmpty ? nil : { graph.actions.play(songs) },
                        shuffle: songs.isEmpty ? nil : { graph.actions.shuffle(songs) }
                    ) {
                        VStack(spacing: 3) {
                            Text(
                                [
                                    d.playlist.owner.map { "by \($0)" },
                                    Format.count(songs.count, "track"),
                                    Format.duration(Int64(songs.reduce(0) { $0 + ($1.duration ?? 0) })),
                                ].compactMap { $0 }.joined(separator: " · ")
                            )
                            .font(KFont.bodySmall.weight(.medium))
                            .foregroundStyle(c.ink3)
                            if let comment = d.playlist.comment, !comment.trimmingCharacters(in: .whitespaces).isEmpty {
                                Text(comment).font(KFont.bodySmall).foregroundStyle(c.ink2)
                            }
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
                } actions: {
                    DownloadToolbarButton(songs: songs, label: d.playlist.name)
                    Menu {
                        Button { graph.actions.playNext(songs) } label: { Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") }
                        Button { graph.actions.enqueue(songs) } label: { Label("Add to queue", systemImage: "text.line.last.and.arrowtriangle.forward") }
                        if editable {
                            Divider()
                            Button {
                                newName = d.playlist.name
                                renaming = true
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) { deleting = true } label: { Label("Delete playlist", systemImage: "trash") }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More")
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
                DetailMessage(icon: "music.note.list", title: "Playlist not found", message: "It may have been deleted on the server.")
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
        DetailScaffold(title: name, selection: selection, songs: songs) {
            DetailHeader(
                eyebrow: "Genre",
                title: name,
                coverId: nil,
                play: songs.isEmpty ? nil : { graph.actions.playWindow(songs, 0) },
                shuffle: songs.isEmpty ? nil : { graph.actions.shuffle(songs) }
            ) {
                Text("\(Format.count(albums.count, "album")) · \(Format.count(songs.count, "track"))")
                    .font(KFont.bodySmall.weight(.medium))
                    .foregroundStyle(theme.colors.ink3)
            }
            if !albums.isEmpty {
                SectionHeader("Albums", icon: "square.stack.fill")
                Shelf(items: albums) { AlbumCard(album: $0) }
            }
            if !songs.isEmpty {
                SectionHeader("Tracks", icon: "music.note")
                SongRows(songs: songs, selection: selection) { graph.actions.playWindow(songs, $0) }
            }
        } actions: {
            DownloadToolbarButton(songs: songs, label: name)
            Button {
                if let seed = songs.randomElement() { graph.actions.startInjektSet(seed) }
            } label: {
                Image(systemName: "sparkles")
            }
            .accessibilityLabel("Start an InjeKt set")
        }
        .task(id: "\(name):\(graph.library.version)") {
            songs = await graph.library.songsOfGenre(name)
            albums = await graph.library.albumsOfGenre(name)
        }
    }
}
