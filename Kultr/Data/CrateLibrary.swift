import Foundation

/** Something that can go into a crate. */
enum CrateItem: Identifiable, Hashable {
    case album(id: String, name: String)
    case artist(id: String, name: String)
    case songs([Song])

    var id: String {
        switch self {
        case .album(let id, _): return "album:\(id)"
        case .artist(let id, _): return "artist:\(id)"
        case .songs(let songs): return "songs:" + songs.map(\.id).joined(separator: ",")
        }
    }

    var title: String {
        switch self {
        case .album(_, let name), .artist(_, let name): return name
        case .songs(let songs): return songs.count == 1 ? songs[0].title : "\(songs.count) tracks"
        }
    }
}

/**
 * Crates and notes: stored with the settings (so a settings backup keeps
 * them), resolved to tracks from the library, and, for a crate that asks for
 * it, kept in step with a playlist on the server.
 */
@MainActor
final class CrateLibrary {
    private unowned let graph: AppGraph
    private var syncing: [String: Task<Void, Never>] = [:]

    init(graph: AppGraph) {
        self.graph = graph
    }

    var all: [Crate] { graph.settings.current.crates }

    func crate(_ id: String) -> Crate? { all.first { $0.id == id } }

    // -------------------------------------------------------------- crates --

    func save(_ crate: Crate) {
        graph.settings.update { s in
            if let at = s.crates.firstIndex(where: { $0.id == crate.id }) { s.crates[at] = crate } else { s.crates.append(crate) }
        }
        if crate.syncPlaylist { scheduleSync(crate.id) }
    }

    func delete(_ crate: Crate) {
        graph.settings.update { $0.crates.removeAll { $0.id == crate.id } }
    }

    /** Whether [item] is in [crate]; songs count as in when all of them are. */
    func contains(_ crate: Crate, _ item: CrateItem) -> Bool {
        switch item {
        case .album(let id, _): return crate.contains(album: id)
        case .artist(let id, _): return crate.contains(artist: id)
        case .songs(let songs): return !songs.isEmpty && songs.allSatisfy { crate.contains(song: $0.id) }
        }
    }

    /** Puts [item] in [crate], or takes it out if it is in. */
    func toggle(_ item: CrateItem, in crateId: String) {
        guard var crate = crate(crateId) else { return }
        let wasIn = contains(crate, item)
        switch item {
        case .album(let id, _): crate.toggle(album: id)
        case .artist(let id, _): crate.toggle(artist: id)
        case .songs(let songs):
            for song in songs where crate.contains(song: song.id) == wasIn { crate.toggle(song: song.id) }
        }
        save(crate)
        graph.messages.show(wasIn ? "Taken out of “\(crate.name)”" : "Added to “\(crate.name)”")
    }

    /** Every track in [crate]: its albums, its artists' tracks and its own tracks, or what fits its rules. */
    func songs(_ crate: Crate) async -> [Song] {
        let library = graph.library
        if let rules = crate.rules {
            return await graph.stations.pool(rules, playableOnly: false).map(\.0).sorted { a, b in
                let x = (Format.sortKey(a.artist), a.album ?? "", a.discNumber ?? 1, a.track ?? 0)
                let y = (Format.sortKey(b.artist), b.album ?? "", b.discNumber ?? 1, b.track ?? 0)
                return x < y
            }
        }
        var out: [Song] = []
        var seen = Set<String>()
        func add(_ songs: [Song]) {
            for song in songs where seen.insert(song.id).inserted { out.append(song) }
        }
        for id in crate.albums { add(await library.songsOfAlbumNow(id)) }
        for id in crate.artists { add(await library.songsOfArtistNow(id)) }
        add(await library.songsByIds(crate.songs))
        return out
    }

    // ----------------------------------------------------------- playlists --

    /** Bring [crate]'s playlist in step soon; several changes in a row make one sync. */
    func scheduleSync(_ crateId: String) {
        syncing[crateId]?.cancel()
        syncing[crateId] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.syncNow(crateId)
            self.syncing[crateId] = nil
        }
    }

    /** Makes the crate's playlist hold exactly its tracks, creating it the first time. */
    @discardableResult
    func syncNow(_ crateId: String) async -> String? {
        guard let crate = crate(crateId), crate.syncPlaylist else { return nil }
        let songs = await songs(crate)
        let result = await graph.library.fillPlaylist(crate.playlistId, name: crate.name, songs)
        if let id = result.id, id != crate.playlistId, var fresh = self.crate(crateId) {
            fresh.playlistId = id
            graph.settings.update { s in
                if let at = s.crates.firstIndex(where: { $0.id == crateId }) { s.crates[at] = fresh }
            }
        }
        if let error = result.error { graph.messages.error("“\(crate.name)” could not be synced as a playlist: \(error)") }
        return result.error
    }

    // --------------------------------------------------------------- notes --

    func annotation(_ key: String) -> Annotation {
        graph.settings.current.annotations[key] ?? Annotation()
    }

    func setAnnotation(_ key: String, _ annotation: Annotation) {
        graph.settings.update { s in
            if annotation.isEmpty { s.annotations[key] = nil } else { s.annotations[key] = annotation }
        }
    }
}
