import Foundation
import Observation
import SwiftUI

enum LibraryTab: String, CaseIterable, Hashable {
    case albums, artists, songs, playlists, genres, favourites, downloads, radio

    var label: String {
        switch self {
        case .albums: return "Albums"
        case .artists: return "Artists"
        case .songs: return "Songs"
        case .playlists: return "Playlists"
        case .genres: return "Genres"
        case .favourites: return "Favourites"
        case .downloads: return "Downloads"
        case .radio: return "Radio"
        }
    }
}

enum DownloadsPage: String, CaseIterable, Hashable {
    case now, offline

    var label: String { self == .now ? "Downloading" : "On this phone" }
}

enum MainTab: String, CaseIterable, Hashable {
    case home, library, search, settings

    var label: String {
        switch self {
        case .home: return "Home"
        case .library: return "Library"
        case .search: return "Search"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .library: return "square.stack.fill"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape.fill"
        }
    }
}

enum Route: Hashable {
    case library(LibraryTab)
    case album(String)
    case artist(String)
    case playlist(String)
    case genre(String)
    case sync
    case stats
    case downloads(DownloadsPage)
}

/** Where the sign-in screen should start when it is opened over the app. */
struct LoginRequest: Equatable {
    var url = ""
    var user = ""
}

/** Navigation and the dialogs any screen can ask for; the root view shows them. */
@MainActor
@Observable
final class AppUI {
    var tab: MainTab = .home
    var path: [Route] = []
    var playerOpen = false
    var login: LoginRequest?
    var addToPlaylist: [Song]?
    var rate: Song?
    var sleepTimer = false
    let drag = DragDropState()

    /** The Downloads page shows everything the download strip would. */
    var onDownloadsPage: Bool {
        if case .downloads = path.last { return true }
        return false
    }

    /** The tab the bar lights up: the Library tab while a library page is open on top. */
    var highlightedTab: MainTab {
        for route in path.reversed() {
            if case .library = route { return .library }
        }
        return tab
    }
}

/**
 * Everything a screen can ask the app to do: navigate, play, change the
 * library. Screens reach it as `graph.actions`.
 */
@MainActor
final class AppActions {
    private unowned let graph: AppGraph

    init(graph: AppGraph) {
        self.graph = graph
    }

    private var ui: AppUI { graph.ui }
    private var player: PlayerController { graph.player }
    private var messages: UiMessages { graph.messages }

    // --------------------------------------------------------- navigation --

    func navigate(_ route: Route) {
        ui.playerOpen = false
        if ui.path.last == route { return }
        ui.path.append(route)
    }

    func back() {
        if !ui.path.isEmpty { ui.path.removeLast() }
    }

    func openPlayer() {
        withAnimation(.easeOut(duration: 0.32)) { ui.playerOpen = true }
    }

    func closePlayer() {
        withAnimation(.easeIn(duration: 0.26)) { ui.playerOpen = false }
    }

    /** A tab always opens at its own start page. */
    func selectTab(_ tab: MainTab) {
        if ui.tab == tab && ui.path.isEmpty { return }
        ui.tab = tab
        ui.path = []
    }

    func openAlbum(_ id: String?) {
        if let id, !id.isEmpty { navigate(.album(id)) }
    }

    func openArtist(_ id: String?) {
        if let id, !id.isEmpty { navigate(.artist(id)) }
    }

    func openPlaylist(_ id: String) { navigate(.playlist(id)) }
    func openGenre(_ name: String) { navigate(.genre(name)) }
    func openLibrary(_ tab: LibraryTab) { navigate(.library(tab)) }
    func openDownloads(_ page: DownloadsPage = .now) { navigate(.downloads(page)) }

    // ------------------------------------------------------------ playing --

    func play(_ songs: [Song], _ startIndex: Int = 0) {
        player.play(songs, startIndex: startIndex, shuffle: false)
    }

    /** Play from [index] of a (possibly huge) list without sending the whole library to the player. */
    func playWindow(_ songs: [Song], _ index: Int) {
        let from = max(0, index - 200)
        let to = min(songs.count, index + 800)
        play(Array(songs[from..<to]), index - from)
    }

    func shuffle(_ songs: [Song]) {
        if songs.isEmpty { return }
        player.play(songs.shuffled(), startIndex: 0, shuffle: true)
    }

    func playNext(_ songs: [Song]) { player.playNext(songs) }
    func enqueue(_ songs: [Song]) { player.enqueue(songs) }

    func addToPlaylist(_ songs: [Song]) {
        if !songs.isEmpty { ui.addToPlaylist = songs }
    }

    func rate(_ song: Song) {
        ui.rate = song
    }

    // ------------------------------------------------------------ library --

    private func report(_ error: String?, _ success: String? = nil) {
        if let error {
            messages.error(error)
        } else if let success {
            messages.show(success, .success)
        }
    }

    func setFavourite(_ song: Song, _ starred: Bool) {
        Task { report(await graph.library.setStarred(song, starred), starred ? "Added to favourites" : nil) }
    }

    func setFavourite(_ songs: [Song], _ starred: Bool) {
        Task {
            report(
                await graph.library.setStarred(songs, starred),
                starred ? "Added \(songs.count) to favourites" : "Removed \(songs.count) from favourites"
            )
        }
    }

    func setAlbumFavourite(_ album: Album, _ starred: Bool) {
        Task { report(await graph.library.setAlbumStarred(album, starred), starred ? "Added “\(album.name)” to favourites" : nil) }
    }

    func setArtistFavourite(_ artist: Artist, _ starred: Bool) {
        Task { report(await graph.library.setArtistStarred(artist, starred), starred ? "Added “\(artist.name)” to favourites" : nil) }
    }

    func setRating(_ song: Song, _ rating: Int) {
        Task { report(await graph.library.setRating(song, rating), rating > 0 ? "Rated \(rating) ★" : "Rating cleared") }
    }

    func download(_ songs: [Song], _ label: String? = nil) {
        Task { await graph.offline.download(songs, label: label) }
    }

    func removeDownloads(_ songs: [Song]) {
        Task {
            let removed = await graph.offline.remove(songs.map { $0.id })
            messages.show(removed > 0 ? "Removed \(removed) download\(removed == 1 ? "" : "s")." : "Nothing to remove.")
        }
    }

    /** Start a flowing set from [seed] (or a random track), continued by InjeKt. */
    func startInjektSet(_ seed: Song? = nil) {
        Task {
            var start = seed
            if start == nil { start = await graph.library.randomSongs(1).first }
            guard let start else {
                messages.show("Sync your library first.")
                return
            }
            let rest = await AutoQueue(graph: graph).build(seed: start, recent: [], count: 24)
            play([start] + rest, 0)
            openPlayer()
        }
    }

    /** Something dragged onto the drop zone: resolve it to tracks and do what the target says. */
    func drop(_ payload: DragPayload, _ action: DropAction) {
        Task {
            let songs = await payload.resolve().filter { !$0.isRadio }
            if songs.isEmpty {
                messages.show("“\(payload.label)” has no tracks here yet.")
                return
            }
            switch action {
            case .playNext:
                playNext(songs)
            case .queue:
                enqueue(songs)
            case .favourite:
                let missing = songs.filter { !$0.isStarred }
                if missing.isEmpty {
                    messages.show("Already in your favourites.")
                } else {
                    report(
                        await graph.library.setStarred(missing, true),
                        "Favourited \(missing.count) track\(missing.count == 1 ? "" : "s")"
                    )
                }
            case .download:
                await graph.offline.download(songs, label: payload.label)
            case .remove:
                let removed = await graph.offline.remove(songs.map { $0.id })
                messages.show(
                    removed > 0
                        ? "Removed \(removed) download\(removed == 1 ? "" : "s")."
                        : "Nothing from “\(payload.label)” was downloaded."
                )
            }
        }
    }

    // ------------------------------------------------------------ helpers --

    /** An artist's tracks from the mirror, or album by album from the server when not synced. */
    func artistSongs(_ artist: Artist) async -> [Song] {
        let local = await graph.library.songsOfArtistNow(artist.id)
        if !local.isEmpty { return local }
        guard let client = graph.auth.client else { return [] }
        let remote: Artist? = try? await client.getArtist(artist.id)
        let albums = remote?.album ?? []
        var songs: [Song] = []
        for album in albums { songs += await graph.library.songsOfAlbumNow(album.id) }
        return songs
    }

    /** A playlist's tracks from the mirror, or from the server when its contents are not synced. */
    func playlistSongs(_ playlist: Playlist) async -> [Song] {
        let local = await graph.library.playlist(playlist.id)?.songs ?? []
        if !local.isEmpty { return local }
        guard let client = graph.auth.client else { return [] }
        let remote: Playlist? = try? await client.getPlaylist(playlist.id)
        return remote?.entry ?? []
    }
}
