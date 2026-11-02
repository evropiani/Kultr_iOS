import Foundation

/**
 * Your own note and tags on an album or an artist. Private: kept with your
 * settings (and in a settings backup), never sent to the server.
 */
struct Annotation: Codable, Hashable {
    var note: String = ""
    var tags: [String] = []

    init(note: String = "", tags: [String] = []) {
        self.note = note
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
    }

    var isEmpty: Bool { note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && tags.isEmpty }

    static func albumKey(_ id: String) -> String { "album:\(id)" }
    static func artistKey(_ id: String) -> String { "artist:\(id)" }

    /** Adds [tag] unless it is there already, in any case. */
    mutating func addTag(_ tag: String) {
        let clean = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !tags.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) else { return }
        tags.append(clean)
    }

    mutating func removeTag(_ tag: String) {
        tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }
}

/** Every tag in use and how often, most used first, then by name. */
func tagCounts(_ annotations: [String: Annotation]) -> [(tag: String, count: Int)] {
    var counts: [String: (name: String, count: Int)] = [:]
    for annotation in annotations.values {
        for tag in annotation.tags {
            let key = tag.lowercased()
            counts[key, default: (tag, 0)].count += 1
        }
    }
    return counts.values
        .map { (tag: $0.name, count: $0.count) }
        .sorted { a, b in a.count != b.count ? a.count > b.count : a.tag.localizedCaseInsensitiveCompare(b.tag) == .orderedAscending }
}

/** The album and artist ids carrying any of [tags]. */
func taggedIds(_ annotations: [String: Annotation], tags: [String]) -> Set<String> {
    let wanted = Set(tags.map { $0.lowercased() })
    guard !wanted.isEmpty else { return [] }
    var ids = Set<String>()
    for (key, annotation) in annotations where annotation.tags.contains(where: { wanted.contains($0.lowercased()) }) {
        if let colon = key.firstIndex(of: ":") { ids.insert(String(key[key.index(after: colon)...])) }
    }
    return ids
}

/**
 * A crate: a folder of albums, artists and tracks, filled by hand, or by rules
 * like "4 stars and up, added this year". It can be kept in step with a
 * playlist on the server.
 */
struct Crate: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var icon: String
    var albums: [String] = []
    var artists: [String] = []
    var songs: [String] = []
    /** Filled by these rules instead of by hand; nil for a crate filled by hand. */
    var rules: Station?
    /** Kept in step with a playlist of the same name on the server. */
    var syncPlaylist = false
    /** That playlist, once made. */
    var playlistId: String?

    init(id: String = UUID().uuidString, name: String, icon: String = "shippingbox.fill", rules: Station? = nil) {
        self.id = id
        self.name = name
        self.icon = icon
        self.rules = rules
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: .name)) ?? "Crate"
        icon = (try? c.decode(String.self, forKey: .icon)) ?? "shippingbox.fill"
        albums = (try? c.decodeIfPresent([String].self, forKey: .albums)) ?? []
        artists = (try? c.decodeIfPresent([String].self, forKey: .artists)) ?? []
        songs = (try? c.decodeIfPresent([String].self, forKey: .songs)) ?? []
        rules = try? c.decodeIfPresent(Station.self, forKey: .rules)
        syncPlaylist = (try? c.decodeIfPresent(Bool.self, forKey: .syncPlaylist)) ?? false
        playlistId = try? c.decodeIfPresent(String.self, forKey: .playlistId)
    }

    var byRules: Bool { rules != nil }
    var isEmpty: Bool { albums.isEmpty && artists.isEmpty && songs.isEmpty }

    /** "3 albums · 12 tracks", for a crate filled by hand. */
    var contents: String {
        let parts = [
            albums.isEmpty ? nil : count(albums.count, "album"),
            artists.isEmpty ? nil : count(artists.count, "artist"),
            songs.isEmpty ? nil : count(songs.count, "track"),
        ].compactMap { $0 }
        return parts.isEmpty ? "Empty" : parts.joined(separator: " · ")
    }

    private func count(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

    func contains(album id: String) -> Bool { albums.contains(id) }
    func contains(artist id: String) -> Bool { artists.contains(id) }
    func contains(song id: String) -> Bool { songs.contains(id) }

    /** In if it was out, out if it was in. */
    mutating func toggle(album id: String) { toggle(&albums, id) }
    mutating func toggle(artist id: String) { toggle(&artists, id) }
    mutating func toggle(song id: String) { toggle(&songs, id) }

    private func toggle(_ list: inout [String], _ id: String) {
        if let at = list.firstIndex(of: id) { list.remove(at: at) } else { list.append(id) }
    }
}
