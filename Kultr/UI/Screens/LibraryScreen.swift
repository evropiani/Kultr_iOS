import SwiftUI

private enum AlbumSort: String, CaseIterable {
    case name = "Name", artist = "Artist", year = "Year", added = "Recently added", plays = "Most played"
}

private enum SongSort: String, CaseIterable {
    case title = "Title", artist = "Artist", album = "Album", added = "Recently added", plays = "Most played", rating = "Rating"
}

/**
 * The Library tab, as in Apple Music: its sections as a list, then the
 * albums added most recently.
 */
struct LibraryHome: View {
    @Environment(\.kultr) private var theme
    @State private var recent: [Album] = []

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        let sections = LibraryTab.shown
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(sections, id: \.self) { tab in
                        Button { graph.actions.openLibrary(tab) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: tab.icon)
                                    .font(.title3)
                                    .foregroundStyle(c.accent)
                                    .frame(width: 28)
                                Text(tab.label)
                                    .font(.title3)
                                    .foregroundStyle(c.ink)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(c.ink4)
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                        if tab != sections.last { Rule().padding(.leading, 42) }
                    }
                }
                .padding(.horizontal, 16)
                if !recent.isEmpty {
                    SectionHeader("Recently added")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)], spacing: 16) {
                        ForEach(recent) { AlbumCard(album: $0) }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 24)
        }
        .navigationTitle("Library")
        .kultrScreen()
        .task(id: graph.library.version) { recent = await graph.library.recentlyAdded(12) }
    }
}

/** One section of the library, opened from the list, filtered from the search field under its title. */
struct LibraryScreen: View {
    let tab: LibraryTab
    @State private var filter = ""

    var body: some View {
        // Trimmed and lowercased once, for the page's matches().
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        Group {
            switch tab {
            case .albums: AlbumsTab(query: query)
            case .artists: ArtistsTab(query: query)
            case .songs: SongsTab(query: query)
            case .playlists: PlaylistsTab(query: query)
            case .crates: CratesTab(query: query)
            case .tags: TagsTab(query: query)
            case .genres: GenresTab(query: query)
            case .favourites: FavouritesTab()
            case .downloads: OfflineContent()
            case .radio: RadioTab(query: query)
            }
        }
        .modifier(SectionFilter(tab: tab, text: $filter))
        .navigationTitle(tab.label)
        .navigationBarTitleDisplayMode(.inline)
        .kultrScreen()
    }
}

/** The search field under a section's title; Favourites and Downloads have nothing to filter. */
private struct SectionFilter: ViewModifier {
    let tab: LibraryTab
    @Binding var text: String

    func body(content: Content) -> some View {
        if tab == .favourites || tab == .downloads {
            content
        } else {
            content.searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Filter \(tab.label.lowercased())")
        }
    }
}

private func matches(_ needle: String, _ values: String?...) -> Bool {
    needle.isEmpty || values.contains { ($0 ?? "").lowercased().contains(needle) }
}

private struct SortMenu<Option: Hashable>: View {
    let current: Option
    let options: [Option]
    let label: (Option) -> String
    let onPick: (Option) -> Void

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(label(option)) { onPick(option) }
            }
        } label: {
            PillLabel(text: label(current), icon: "arrow.up.arrow.down")
        }
        .menuOrder(.fixed)
    }
}

/** A pill's look without its button, for menus. */
struct PillLabel: View {
    @Environment(\.kultr) private var theme
    let text: String
    var icon: String?

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).frame(width: 18, height: 18)
            }
            Text(text).font(KFont.labelLarge).lineLimit(1)
        }
        .foregroundStyle(theme.colors.accent)
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(Capsule().fill(theme.colors.sand))
    }
}

/** A Library page with nothing in it, because the library has not been synced or read yet. */
struct EmptyLibrary: View {
    let tab: LibraryTab

    private var copy: (title: String, message: String) {
        let local = AppGraph.shared.isLocal
        let fill = local
            ? "Choose the folders your music is in, and Kultr reads them."
            : "Kultr keeps a copy of your library on this phone. Sync it once, and after that only changes are fetched."
        switch tab {
        case .albums: return ("No albums yet", fill)
        case .artists: return ("No artists yet", fill)
        case .songs: return ("No tracks yet", fill)
        case .genres: return ("No genres yet", "Genres come from the tags in your music. " + fill)
        default: return ("Nothing here yet", fill)
        }
    }

    var body: some View {
        EmptyState(icon: tab.icon, title: copy.title, message: copy.message) {
            Pill(AppGraph.shared.isLocal ? "Open Sync" : "Sync my library", icon: "arrow.triangle.2.circlepath", accent: true) {
                AppGraph.shared.actions.navigate(.sync)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// ---------------------------------------------------------------- albums --

private struct AlbumsTab: View {
    @Environment(\.kultr) private var theme
    let query: String
    @State private var albums: [Album]?
    @State private var shown: [Album] = []
    @State private var sort: AlbumSort = .name

    var body: some View {
        let graph = AppGraph.shared
        Group {
            if let albums {
                if albums.isEmpty {
                    EmptyLibrary(tab: .albums)
                } else {
                    ScrollView {
                        if shown.isEmpty && !query.isEmpty {
                            NoMatches(query: query, what: "albums")
                        } else {
                            LazyVGrid(columns: theme.settings.gridSize.columns, spacing: 16) {
                                Section {
                                    ForEach(shown) { AlbumCard(album: $0) }
                                } header: {
                                    HStack {
                                        Text(Format.count(shown.count, "album")).foregroundStyle(theme.colors.ink3)
                                        Spacer()
                                        SortMenu(current: sort, options: AlbumSort.allCases, label: { $0.rawValue }) { sort = $0 }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            .padding(16)
                        }
                    }
                }
            } else {
                ScrollView { SkeletonGrid() }.scrollDisabled(true)
            }
        }
        .task(id: graph.library.version) { albums = await graph.library.albums() }
        .task(id: "\(albums?.count ?? -1):\(query):\(sort.rawValue):\(graph.library.version)") { refresh() }
    }

    private func refresh() {
        let filtered = (albums ?? []).filter { matches(query, $0.name, $0.artist) }
        switch sort {
        case .name: shown = filtered.sorted { Format.sortKey($0.name) < Format.sortKey($1.name) }
        case .artist:
            shown = filtered.sorted {
                let a = Format.sortKey($0.artist), b = Format.sortKey($1.artist)
                return a != b ? a < b : ($0.year ?? 0) < ($1.year ?? 0)
            }
        case .year: shown = filtered.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .added: shown = filtered.sorted { ($0.created ?? "") > ($1.created ?? "") }
        case .plays: shown = filtered.sorted { ($0.playCount ?? 0) > ($1.playCount ?? 0) }
        }
    }
}

// --------------------------------------------------------------- artists --

private struct ArtistsTab: View {
    @Environment(\.kultr) private var theme
    let query: String
    @State private var artists: [Artist]?

    var body: some View {
        let graph = AppGraph.shared
        Group {
            if let artists {
                if artists.isEmpty {
                    EmptyLibrary(tab: .artists)
                } else {
                    let shown = artists.filter { matches(query, $0.name) }
                    ScrollView {
                        if shown.isEmpty && !query.isEmpty {
                            NoMatches(query: query, what: "artists")
                        } else {
                            LazyVGrid(columns: theme.settings.gridSize.columns, spacing: 16) {
                                Section {
                                    ForEach(shown) { ArtistCard(artist: $0) }
                                } header: {
                                    Text(Format.count(shown.count, "artist"))
                                        .foregroundStyle(theme.colors.ink3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 4)
                                }
                            }
                            .padding(16)
                        }
                    }
                }
            } else {
                ScrollView { SkeletonGrid(round: true) }.scrollDisabled(true)
            }
        }
        .task(id: graph.library.version) { artists = await graph.library.artists() }
    }
}

// ----------------------------------------------------------------- songs --

private struct SongsTab: View {
    @Environment(\.kultr) private var theme
    let query: String
    @State private var songs: [Song]?
    @State private var shown: [Song] = []
    @State private var sort: SongSort = .title
    @State private var selection = SongSelection()

    var body: some View {
        let graph = AppGraph.shared
        Group {
            if let songs {
                if songs.isEmpty {
                    EmptyLibrary(tab: .songs)
                } else {
                    VStack(spacing: 0) {
                        SelectionBar(selection: selection, songs: shown)
                        // A List recycles its rows, so ten thousand tracks scroll as smoothly as ten.
                        List {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    Pill("Play", icon: "play.fill", accent: true) { graph.actions.play(Array(shown.prefix(1000))) }
                                    Pill("Shuffle", icon: "shuffle") { graph.actions.shuffle(Array(shown.shuffled().prefix(1000))) }
                                    SortMenu(current: sort, options: SongSort.allCases, label: { $0.rawValue }) { sort = $0 }
                                    Text(Format.count(shown.count, "track")).font(KFont.bodySmall).foregroundStyle(theme.colors.ink3)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            if shown.isEmpty && !query.isEmpty {
                                NoMatches(query: query, what: "tracks")
                                    .listRowInsets(EdgeInsets())
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            }
                            SongRows(songs: shown, selection: selection) { index in
                                graph.actions.playWindow(shown, index)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .environment(\.defaultMinListRowHeight, 1)
                    }
                }
            } else {
                ScrollView { SkeletonRows(count: 12).padding(.top, 52) }.scrollDisabled(true)
            }
        }
        .task(id: graph.library.version) { songs = await graph.library.songs() }
        .task(id: "\(songs?.count ?? -1):\(query):\(sort.rawValue):\(graph.library.version)") {
            let all = songs ?? []
            let needle = query
            let sort = self.sort
            // Sorting a big library takes a moment; never on the main thread.
            let result = await Task.detached(priority: .userInitiated) { Self.arrange(all, needle, sort) }.value
            if !Task.isCancelled { shown = result }
        }
    }

    nonisolated private static func arrange(_ songs: [Song], _ needle: String, _ sort: SongSort) -> [Song] {
        let filtered = songs.filter { matches(needle, $0.title, $0.artist, $0.album) }
        switch sort {
        case .title:
            return filtered
        case .artist:
            return filtered.sorted {
                let a = Format.sortKey($0.artist), b = Format.sortKey($1.artist)
                if a != b { return a < b }
                if ($0.album ?? "") != ($1.album ?? "") { return ($0.album ?? "") < ($1.album ?? "") }
                return ($0.track ?? 0) < ($1.track ?? 0)
            }
        case .album:
            return filtered.sorted {
                let a = Format.sortKey($0.album), b = Format.sortKey($1.album)
                if a != b { return a < b }
                if ($0.discNumber ?? 1) != ($1.discNumber ?? 1) { return ($0.discNumber ?? 1) < ($1.discNumber ?? 1) }
                return ($0.track ?? 0) < ($1.track ?? 0)
            }
        case .added: return filtered.sorted { ($0.created ?? "") > ($1.created ?? "") }
        case .plays: return filtered.sorted { ($0.playCount ?? 0) > ($1.playCount ?? 0) }
        case .rating: return filtered.sorted { ($0.userRating ?? 0) > ($1.userRating ?? 0) }
        }
    }
}

// ------------------------------------------------------------- playlists --

private struct PlaylistsTab: View {
    @Environment(\.kultr) private var theme
    let query: String
    @State private var playlists: [Playlist]?
    @State private var creating = false
    @State private var newName = ""
    @State private var refreshing = false

    var body: some View {
        let graph = AppGraph.shared
        Group {
            if let playlists {
                let shown = playlists.filter { matches(query, $0.name) }
                ScrollView {
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Pill("New playlist", icon: "plus", accent: true) {
                                newName = ""
                                creating = true
                            }
                            Pill(refreshing ? "Refreshing…" : "Refresh", icon: "arrow.clockwise", enabled: !refreshing) {
                                refreshing = true
                                Task {
                                    if let error = await graph.library.refreshPlaylists() { graph.messages.error(error) }
                                    refreshing = false
                                }
                            }
                            Spacer()
                        }
                        .padding(.bottom, 12)
                        if shown.isEmpty && !query.isEmpty {
                            NoMatches(query: query, what: "playlists")
                        } else if shown.isEmpty {
                            // Across the whole page, not in the grid's first column.
                            EmptyState(
                                icon: "music.note.list",
                                title: "No playlists yet",
                                message: "Tap New playlist, or choose Add to playlist in any track's ••• menu. Playlists on your server show up here too."
                            )
                            .padding(.top, 24)
                        } else {
                            LazyVGrid(columns: theme.settings.gridSize.columns, spacing: 16) {
                                ForEach(shown) { PlaylistCard(playlist: $0) }
                            }
                        }
                    }
                    .padding(16)
                }
            } else {
                ScrollView { SkeletonGrid() }.scrollDisabled(true)
            }
        }
        .task(id: graph.library.version) { playlists = await graph.library.playlists() }
        .alert("New playlist", isPresented: $creating) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = newName
                Task { if let error = await graph.library.createPlaylist(name, []) { graph.messages.error(error) } }
            }
            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

// ---------------------------------------------------------------- genres --

private struct GenresTab: View {
    @Environment(\.kultr) private var theme
    let query: String
    @State private var genres: [Genre]?

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        Group {
            if let genres {
                if genres.isEmpty {
                    EmptyLibrary(tab: .genres)
                } else {
                    let shown = genres.filter { matches(query, $0.value) }
                    ScrollView {
                        if shown.isEmpty && !query.isEmpty { NoMatches(query: query, what: "genres") }
                        LazyVStack(spacing: 0) {
                            ForEach(shown) { genre in
                                HStack(spacing: 12) {
                                    Artwork(coverId: nil, size: 44, label: genre.value)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(genre.value).font(KFont.bodyLarge).foregroundStyle(c.ink).lineLimit(1)
                                        Text([genre.songCount.map { Format.count($0, "track") }, genre.albumCount.map { Format.count($0, "album") }].compactMap { $0 }.joined(separator: " · "))
                                            .font(KFont.bodySmall)
                                            .foregroundStyle(c.ink3)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    IconButton(icon: "shuffle", tint: c.ink2, label: "Shuffle \(genre.value)") {
                                        Task { graph.actions.shuffle(await graph.library.songsOfGenre(genre.value)) }
                                    }
                                }
                                .padding(.leading, 16)
                                .padding(.trailing, 4)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                                .onTapGesture { graph.actions.openGenre(genre.value) }
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            } else {
                ScrollView { SkeletonRows(count: 12) }.scrollDisabled(true)
            }
        }
        .task(id: graph.library.version) { genres = await graph.library.genres() }
    }
}

// ------------------------------------------------------------ favourites --

private struct FavouritesTab: View {
    @Environment(\.kultr) private var theme
    @State private var songs: [Song] = []
    @State private var albums: [Album] = []
    @State private var artists: [Artist] = []
    @State private var loaded = false
    @State private var selection = SongSelection()

    var body: some View {
        let graph = AppGraph.shared
        Group {
            if loaded && songs.isEmpty && albums.isEmpty && artists.isEmpty {
                EmptyState(
                    icon: "heart",
                    title: "No favourites yet",
                    message: "Tap the heart on a track, an album or an artist, or double-tap the cover in the player. What you heart shows up here, and on your server."
                )
                .frame(maxHeight: .infinity)
            } else if !loaded {
                ScrollView { SkeletonRows(count: 10).padding(.top, 52) }.scrollDisabled(true)
            } else {
                VStack(spacing: 0) {
                    SelectionBar(selection: selection, songs: songs)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            let missing = graph.offline.missing(songs)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    Pill("Play", icon: "play.fill", accent: true, enabled: !songs.isEmpty) { graph.actions.play(songs) }
                                    Pill("Shuffle", icon: "shuffle", enabled: !songs.isEmpty) { graph.actions.shuffle(songs) }
                                    Pill(missing == 0 ? "Downloaded" : "Download", icon: "arrow.down.circle", enabled: missing > 0, badge: missing > 0 ? "\(missing)" : nil) {
                                        graph.actions.download(songs, "Your favourites")
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                            if !albums.isEmpty {
                                SectionHeader("Albums")
                                Shelf(items: albums) { AlbumCard(album: $0) }
                            }
                            if !artists.isEmpty {
                                SectionHeader("Artists")
                                Shelf(items: artists, cardWidth: 130) { ArtistCard(artist: $0) }
                            }
                            if !songs.isEmpty {
                                SectionHeader("Tracks")
                                SongRows(songs: songs, selection: selection) { graph.actions.play(songs, $0) }
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .task(id: graph.library.version) {
            songs = await graph.library.starredSongs()
            albums = await graph.library.starredAlbums()
            artists = await graph.library.starredArtists()
            loaded = true
        }
    }
}

// ----------------------------------------------------------------- radio --

private struct RadioTab: View {
    @Environment(\.kultr) private var theme
    let query: String
    @State private var stations: [RadioStation]?
    @State private var error: String?

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        let favourites = theme.settings.favouriteRadios
        Group {
            if let stations {
                if stations.isEmpty {
                    EmptyState(
                        icon: "dot.radiowaves.left.and.right",
                        title: error == nil ? "No radio stations" : "Couldn't load the stations",
                        message: error ?? "Internet radio stations are set up on your server. In Navidrome, open Radios and add a stream; it shows up here."
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    let shown = stations.filter { matches(query, $0.name) }
                        .enumerated()
                        .sorted { lhs, rhs in
                            let a = favourites.contains(lhs.element.id), b = favourites.contains(rhs.element.id)
                            return a != b ? a : lhs.offset < rhs.offset
                        }
                        .map { $0.element }
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(shown) { station in
                                let favourite = favourites.contains(station.id)
                                HStack(spacing: 12) {
                                    Artwork(coverId: nil, size: 44, label: station.name)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(station.name).font(KFont.bodyLarge).foregroundStyle(c.ink).lineLimit(1)
                                        Text(station.homePageUrl ?? station.streamUrl).font(KFont.bodySmall).foregroundStyle(c.ink3).lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    IconButton(icon: favourite ? "heart.fill" : "heart", tint: favourite ? c.accent : c.ink3, label: favourite ? "Unfavourite" : "Favourite") {
                                        graph.settings.update { s in
                                            if favourite {
                                                s.favouriteRadios.removeAll { $0 == station.id }
                                            } else {
                                                s.favouriteRadios.append(station.id)
                                            }
                                        }
                                    }
                                }
                                .padding(.leading, 16)
                                .padding(.trailing, 4)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                                .onTapGesture { graph.actions.play([station.asSong()]) }
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            } else {
                ScrollView { SkeletonRows(count: 8) }.scrollDisabled(true)
            }
        }
        .task {
            do {
                stations = try await graph.library.radioStations()
            } catch {
                self.error = describeError(error)
                stations = []
            }
        }
    }
}
