import SwiftUI

private enum AlbumSort: String, CaseIterable {
    case name = "Name", artist = "Artist", year = "Year", added = "Recently added", plays = "Most played"
}

private enum SongSort: String, CaseIterable {
    case title = "Title", artist = "Artist", album = "Album", added = "Recently added", plays = "Most played", rating = "Rating"
}

struct LibraryScreen: View {
    @Environment(\.kultr) private var theme
    let initialTab: LibraryTab
    @State private var tab: LibraryTab?
    @State private var query = ""

    var body: some View {
        let c = theme.colors
        let current = tab ?? initialTab
        VStack(spacing: 0) {
            Text("Library")
                .font(KFont.headlineMedium)
                .tracking(-0.3)
                .foregroundStyle(c.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(LibraryTab.allCases, id: \.self) { entry in
                            let on = entry == current
                            Button {
                                tab = entry
                                query = ""
                            } label: {
                                VStack(spacing: 8) {
                                    Text(entry.label)
                                        .font(KFont.titleSmall)
                                        .foregroundStyle(on ? c.accent : c.ink2)
                                    Capsule()
                                        .fill(on ? c.accent : .clear)
                                        .frame(height: 3)
                                }
                                .padding(.horizontal, 14)
                                .padding(.top, 10)
                                .fixedSize()
                            }
                            .buttonStyle(PressableStyle())
                            .id(entry)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .overlay(alignment: .bottom) { Rule() }
                .onAppear { proxy.scrollTo(current, anchor: .center) }
            }
            if current != .favourites && current != .downloads {
                FilterField(text: $query, placeholder: "Filter \(current.label.lowercased())")
            }
            Group {
                switch current {
                case .albums: AlbumsTab(query: query)
                case .artists: ArtistsTab(query: query)
                case .songs: SongsTab(query: query)
                case .playlists: PlaylistsTab(query: query)
                case .genres: GenresTab(query: query)
                case .favourites: FavouritesTab()
                case .downloads: OfflineContent()
                case .radio: RadioTab(query: query)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .kultrScreen()
        .onChange(of: initialTab) { _, value in tab = value }
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
        .foregroundStyle(theme.colors.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(theme.colors.glass))
        .overlay(Capsule().strokeBorder(theme.colors.edge, lineWidth: 1))
    }
}

struct EmptyLibrary: View {
    var body: some View {
        EmptyState(icon: "square.stack.fill", title: "Nothing here yet", message: "Sync your library to browse it on this phone.") {
            Pill("Open Sync", accent: true) { AppGraph.shared.actions.navigate(.sync) }
        }
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
                    EmptyLibrary()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: theme.settings.gridSize.minCell), spacing: 0, alignment: .top)], spacing: 0) {
                            Section {
                                ForEach(shown) { AlbumCard(album: $0) }
                            } header: {
                                HStack {
                                    Text(Format.count(shown.count, "album")).foregroundStyle(theme.colors.ink3)
                                    Spacer()
                                    SortMenu(current: sort, options: AlbumSort.allCases, label: { $0.rawValue }) { sort = $0 }
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                            }
                        }
                        .padding(10)
                    }
                }
            } else {
                LoadingView()
            }
        }
        .task(id: graph.library.version) { albums = await graph.library.albums() }
        .task(id: "\(albums?.count ?? -1):\(query):\(sort.rawValue):\(graph.library.version)") { refresh() }
    }

    private func refresh() {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = (albums ?? []).filter { matches(needle, $0.name, $0.artist) }
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
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        Group {
            if let artists {
                if artists.isEmpty {
                    EmptyLibrary()
                } else {
                    let shown = needle.isEmpty ? artists : artists.filter { matches(needle, $0.name) }
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: theme.settings.gridSize.minCell), spacing: 0, alignment: .top)], spacing: 0) {
                            Section {
                                ForEach(shown) { ArtistCard(artist: $0) }
                            } header: {
                                Text(Format.count(shown.count, "artist"))
                                    .foregroundStyle(theme.colors.ink3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(6)
                            }
                        }
                        .padding(10)
                    }
                }
            } else {
                LoadingView()
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
                    EmptyLibrary()
                } else {
                    VStack(spacing: 0) {
                        if selection.active { SelectionBar(selection: selection, songs: shown) }
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        Pill("Play", icon: "play.fill", accent: true) { graph.actions.play(Array(shown.prefix(1000))) }
                                        Pill("Shuffle", icon: "shuffle") { graph.actions.shuffle(Array(shown.shuffled().prefix(1000))) }
                                        SortMenu(current: sort, options: SongSort.allCases, label: { $0.rawValue }) { sort = $0 }
                                        Text(Format.count(shown.count, "track")).foregroundStyle(theme.colors.ink3)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 4)
                                }
                                SongRows(songs: shown, selection: selection) { index in
                                    graph.actions.playWindow(shown, index)
                                }
                            }
                            .padding(.bottom, 24)
                        }
                    }
                }
            } else {
                LoadingView()
            }
        }
        .task(id: graph.library.version) { songs = await graph.library.songs() }
        .task(id: "\(songs?.count ?? -1):\(query):\(sort.rawValue):\(graph.library.version)") { refresh() }
    }

    private func refresh() {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = (songs ?? []).filter { matches(needle, $0.title, $0.artist, $0.album) }
        switch sort {
        case .title: shown = filtered
        case .artist:
            shown = filtered.sorted {
                let a = Format.sortKey($0.artist), b = Format.sortKey($1.artist)
                if a != b { return a < b }
                if ($0.album ?? "") != ($1.album ?? "") { return ($0.album ?? "") < ($1.album ?? "") }
                return ($0.track ?? 0) < ($1.track ?? 0)
            }
        case .album:
            shown = filtered.sorted {
                let a = Format.sortKey($0.album), b = Format.sortKey($1.album)
                if a != b { return a < b }
                if ($0.discNumber ?? 1) != ($1.discNumber ?? 1) { return ($0.discNumber ?? 1) < ($1.discNumber ?? 1) }
                return ($0.track ?? 0) < ($1.track ?? 0)
            }
        case .added: shown = filtered.sorted { ($0.created ?? "") > ($1.created ?? "") }
        case .plays: shown = filtered.sorted { ($0.playCount ?? 0) > ($1.playCount ?? 0) }
        case .rating: shown = filtered.sorted { ($0.userRating ?? 0) > ($1.userRating ?? 0) }
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
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        Group {
            if let playlists {
                let shown = needle.isEmpty ? playlists : playlists.filter { matches(needle, $0.name) }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: theme.settings.gridSize.minCell), spacing: 0, alignment: .top)], spacing: 0) {
                        Section {
                            if shown.isEmpty {
                                EmptyState(icon: "square.stack.fill", title: "No playlists", message: "Create one, or add tracks to a new playlist from any track's menu.")
                            }
                            ForEach(shown) { PlaylistCard(playlist: $0) }
                        } header: {
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
                            .padding(6)
                        }
                    }
                    .padding(10)
                }
            } else {
                LoadingView()
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
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        Group {
            if let genres {
                if genres.isEmpty {
                    EmptyLibrary()
                } else {
                    let shown = needle.isEmpty ? genres : genres.filter { matches(needle, $0.value) }
                    ScrollView {
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
                                        Task { graph.actions.shuffle(await graph.library.songsOfGenreNow(genre.value)) }
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
                LoadingView()
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
                EmptyState(icon: "heart", title: "No favourites yet", message: "Heart a track, album or artist and it shows up here.")
            } else {
                VStack(spacing: 0) {
                    if selection.active { SelectionBar(selection: selection, songs: songs) }
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
                                SectionHeader("Tracks", icon: "heart.fill")
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
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        Group {
            if let stations {
                if stations.isEmpty {
                    EmptyState(icon: "radio", title: "No radio stations", message: error ?? "Add internet radio stations in Navidrome and they appear here.")
                } else {
                    let shown = (needle.isEmpty ? stations : stations.filter { matches(needle, $0.name) })
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
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                                .onTapGesture { graph.actions.play([station.asSong()]) }
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            } else {
                LoadingView()
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
