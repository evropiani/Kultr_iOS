import Foundation

/**
 * One audio file found in a music folder on the phone, with what its tags say.
 * Everything from the tags is optional: untagged files still get a title from
 * their file name and an album from their folder.
 */
struct LocalTrack: Hashable, Sendable {
    /** Where the file is, as Kultr keeps it (folder id and path inside it). Also what identifies it. */
    var path: String
    var fileName: String
    /** Identifies the folder the file is in, and that folder's name. */
    var folderKey: String
    var folderName: String
    /** Last modified, in milliseconds since the epoch. */
    var modified: Int64
    var size: Int64
    var title: String?
    var artist: String?
    var albumArtist: String?
    var album: String?
    var track: Int?
    var disc: Int?
    var year: Int?
    var genre: String?
    var durationMs: Int64?
    /** Bits per second. */
    var bitRate: Int?
    var sampleRate: Int?
    var mimeType: String?

    init(
        path: String, fileName: String, folderKey: String, folderName: String, modified: Int64, size: Int64,
        title: String? = nil, artist: String? = nil, albumArtist: String? = nil, album: String? = nil,
        track: Int? = nil, disc: Int? = nil, year: Int? = nil, genre: String? = nil, durationMs: Int64? = nil,
        bitRate: Int? = nil, sampleRate: Int? = nil, mimeType: String? = nil
    ) {
        self.path = path
        self.fileName = fileName
        self.folderKey = folderKey
        self.folderName = folderName
        self.modified = modified
        self.size = size
        self.title = title
        self.artist = artist
        self.albumArtist = albumArtist
        self.album = album
        self.track = track
        self.disc = disc
        self.year = year
        self.genre = genre
        self.durationMs = durationMs
        self.bitRate = bitRate
        self.sampleRate = sampleRate
        self.mimeType = mimeType
    }

    /** These tags, put on this file. */
    func with(_ tags: AudioTags) -> LocalTrack {
        var copy = self
        copy.title = tags.title
        copy.artist = tags.artist
        copy.albumArtist = tags.albumArtist
        copy.album = tags.album
        copy.track = tags.track
        copy.disc = tags.disc
        copy.year = tags.year
        copy.genre = tags.genre
        copy.durationMs = tags.durationMs ?? copy.durationMs
        copy.sampleRate = tags.sampleRate ?? copy.sampleRate
        if let ms = copy.durationMs, ms > 0, size > 0 {
            copy.bitRate = Int(Double(size) * 8 / (Double(ms) / 1000))
        }
        return copy
    }
}

/** A local library in the shapes the rest of Kultr knows from a server. */
struct LocalCatalog {
    let songs: [Song]
    let albums: [Album]
    let artists: [Artist]
    let genres: [Genre]
}

/**
 * Turns the tracks found in the chosen folders into songs, albums, artists
 * and genres, as a Subsonic server would list them, so the library pages,
 * home shelves, search and InjeKt work the same on local music.
 *
 * Albums are grouped the way most players do it: by album name and album
 * artist when the files say who the album is by, otherwise by album name
 * within one folder, so two different "Greatest Hits" in two folders stay
 * apart while a two-disc album in CD1 and CD2 folders stays together.
 */
enum LocalCatalogBuilder {
    static let songPrefix = "local:"
    static let albumPrefix = "local-album:"
    static let artistPrefix = "local-artist:"
    static let unknownArtist = "Unknown artist"
    static let variousArtists = "Various artists"

    static func songId(_ path: String) -> String { songPrefix + String(md5Hex(path).prefix(24)) }

    static func artistId(_ name: String) -> String {
        artistPrefix + String(md5Hex(name.trimmingCharacters(in: .whitespaces).lowercased()).prefix(16))
    }

    /** The album a track belongs to: by name and album artist when the file names one, otherwise by name within its folder. */
    static func albumId(_ albumName: String, _ albumArtist: String?, _ folderKey: String) -> String {
        let key = albumArtist.map { "a|\(albumName.lowercased())|\($0.lowercased())" } ?? "f|\(albumName.lowercased())|\(folderKey)"
        return albumPrefix + String(md5Hex(key).prefix(16))
    }

    private static func clean(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static func albumName(_ track: LocalTrack) -> String { clean(track.album) ?? track.folderName }

    /**
     * Build the catalogue. [covers] maps a folder key to the cover for albums
     * in that folder (a cover.jpg and the like). [previous] gives what was
     * known about a song before (play counts, favourites, ratings), which the
     * files themselves cannot say.
     */
    static func build(
        _ tracks: [LocalTrack],
        covers: [String: String] = [:],
        previous: (String) -> Song? = { _ in nil }
    ) -> LocalCatalog {
        var order: [String] = []
        var groups: [String: [LocalTrack]] = [:]
        var seen = Set<String>()
        for track in tracks where seen.insert(track.path).inserted {
            let id = albumId(albumName(track), clean(track.albumArtist), track.folderKey)
            if groups[id] == nil { order.append(id) }
            groups[id, default: []].append(track)
        }

        var songs: [Song] = []
        var albums: [Album] = []
        for albumId in order {
            let group = groups[albumId] ?? []
            guard let first = group.first else { continue }
            let name = albumName(first)
            var trackArtists: [String] = []
            for artist in group.compactMap({ clean($0.artist) }) where !trackArtists.contains(artist) {
                trackArtists.append(artist)
            }
            let albumArtist = clean(first.albumArtist) ?? (trackArtists.count == 0 ? unknownArtist : trackArtists.count == 1 ? trackArtists[0] : variousArtists)
            let albumArtistId = artistId(albumArtist)
            let cover = group.lazy.compactMap { covers[$0.folderKey] }.first

            let albumSongs = group.map { track -> Song in
                let id = songId(track.path)
                let before = previous(id)
                let fileTitle = (track.fileName as NSString).deletingPathExtension
                let suffix = (track.fileName as NSString).pathExtension.lowercased()
                var song = Song(id: id, title: clean(track.title) ?? fileTitle)
                song.parent = albumId
                song.album = name
                song.artist = clean(track.artist) ?? albumArtist
                song.albumId = albumId
                // Artist pages list album artists, so every track links to its album's.
                song.artistId = albumArtistId
                song.track = track.track
                song.discNumber = track.disc
                song.year = track.year
                song.genre = clean(track.genre)
                song.coverArt = cover
                song.size = track.size
                song.contentType = track.mimeType
                song.suffix = suffix.isEmpty ? nil : suffix
                song.duration = track.durationMs.map { Int(($0 + 500) / 1000) }
                song.bitRate = track.bitRate.map { $0 / 1000 }
                song.samplingRate = track.sampleRate
                song.path = track.path
                song.created = Format.iso(track.modified)
                song.playCount = before?.playCount
                song.played = before?.played
                song.starred = before?.starred
                song.userRating = before?.userRating
                return song
            }.sorted { a, b in
                if (a.discNumber ?? 1) != (b.discNumber ?? 1) { return (a.discNumber ?? 1) < (b.discNumber ?? 1) }
                if (a.track ?? Int.max) != (b.track ?? Int.max) { return (a.track ?? Int.max) < (b.track ?? Int.max) }
                return a.title.lowercased() < b.title.lowercased()
            }
            songs += albumSongs

            var genreCounts: [String: Int] = [:]
            for genre in albumSongs.compactMap({ $0.genre }) { genreCounts[genre, default: 0] += 1 }
            let plays = albumSongs.reduce(Int64(0)) { $0 + ($1.playCount ?? 0) }
            var album = Album(id: albumId, name: name)
            album.artist = albumArtist
            album.artistId = albumArtistId
            album.coverArt = cover
            album.songCount = albumSongs.count
            album.duration = albumSongs.reduce(0) { $0 + ($1.duration ?? 0) }
            album.playCount = plays > 0 ? plays : nil
            album.played = albumSongs.compactMap { $0.played }.max()
            album.created = albumSongs.compactMap { $0.created }.max()
            album.year = albumSongs.compactMap { $0.year }.max()
            album.genre = genreCounts.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key
            album.isCompilation = albumArtist == variousArtists
            albums.append(album)
        }

        var artistOrder: [String] = []
        var byArtist: [String: [Album]] = [:]
        for album in albums {
            let id = album.artistId ?? ""
            if byArtist[id] == nil { artistOrder.append(id) }
            byArtist[id, default: []].append(album)
        }
        let artists = artistOrder.map { id -> Artist in
            let own = byArtist[id] ?? []
            var artist = Artist(id: id, name: own.first?.artist ?? "")
            artist.coverArt = own.lazy.compactMap { $0.coverArt }.first
            artist.albumCount = own.count
            return artist
        }

        var genreSongs: [String: Int] = [:]
        var genreAlbums: [String: Set<String>] = [:]
        for song in songs {
            guard let genre = song.genre else { continue }
            genreSongs[genre, default: 0] += 1
            if let albumId = song.albumId { genreAlbums[genre, default: []].insert(albumId) }
        }
        let genres = genreSongs
            .map { Genre(value: $0.key, songCount: $0.value, albumCount: genreAlbums[$0.key]?.count ?? 0) }
            .sorted { ($0.songCount ?? 0, $1.value) > ($1.songCount ?? 0, $0.value) }

        return LocalCatalog(songs: songs, albums: albums, artists: artists, genres: genres)
    }
}
