import Foundation

/*
 * Subsonic API shapes, narrowed to what Navidrome actually returns and what
 * Kultr actually uses. Everything optional is genuinely optional — Navidrome
 * omits empty fields rather than sending nulls.
 */

struct ReplayGain: Codable, Hashable {
    var trackGain: Double?
    var albumGain: Double?
    var trackPeak: Double?
    var albumPeak: Double?

    init(trackGain: Double? = nil, albumGain: Double? = nil, trackPeak: Double? = nil, albumPeak: Double? = nil) {
        self.trackGain = trackGain
        self.albumGain = albumGain
        self.trackPeak = trackPeak
        self.albumPeak = albumPeak
    }

    enum CodingKeys: String, CodingKey {
        case trackGain, albumGain, trackPeak, albumPeak
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trackGain = c.double(.trackGain)
        albumGain = c.double(.albumGain)
        trackPeak = c.double(.trackPeak)
        albumPeak = c.double(.albumPeak)
    }
}

struct Song: Codable, Hashable, Identifiable {
    var id: String
    var parent: String?
    var title: String
    var album: String?
    var artist: String?
    var albumId: String?
    var artistId: String?
    var track: Int?
    var discNumber: Int?
    var year: Int?
    var genre: String?
    var coverArt: String?
    var size: Int64?
    var contentType: String?
    var suffix: String?
    var transcodedContentType: String?
    var transcodedSuffix: String?
    /** Seconds. */
    var duration: Int?
    var bitRate: Int?
    var samplingRate: Int?
    var channelCount: Int?
    var path: String?
    var playCount: Int64?
    var played: String?
    var created: String?
    var starred: String?
    var userRating: Int?
    var averageRating: Double?
    var bpm: Int?
    var comment: String?
    var musicBrainzId: String?
    var isVideo: Bool?
    var type: String?
    var replayGain: ReplayGain?
    /**
     * Kultr-only: play this exact URL instead of building a Subsonic stream
     * URL. Used for internet radio stations, which are not library tracks.
     */
    var kultrStreamUrl: String?

    init(
        id: String,
        parent: String? = nil,
        title: String = "",
        album: String? = nil,
        artist: String? = nil,
        albumId: String? = nil,
        artistId: String? = nil,
        track: Int? = nil,
        discNumber: Int? = nil,
        year: Int? = nil,
        genre: String? = nil,
        coverArt: String? = nil,
        size: Int64? = nil,
        contentType: String? = nil,
        suffix: String? = nil,
        transcodedContentType: String? = nil,
        transcodedSuffix: String? = nil,
        duration: Int? = nil,
        bitRate: Int? = nil,
        samplingRate: Int? = nil,
        channelCount: Int? = nil,
        path: String? = nil,
        playCount: Int64? = nil,
        played: String? = nil,
        created: String? = nil,
        starred: String? = nil,
        userRating: Int? = nil,
        averageRating: Double? = nil,
        bpm: Int? = nil,
        comment: String? = nil,
        musicBrainzId: String? = nil,
        isVideo: Bool? = nil,
        type: String? = nil,
        replayGain: ReplayGain? = nil,
        kultrStreamUrl: String? = nil
    ) {
        self.id = id
        self.parent = parent
        self.title = title
        self.album = album
        self.artist = artist
        self.albumId = albumId
        self.artistId = artistId
        self.track = track
        self.discNumber = discNumber
        self.year = year
        self.genre = genre
        self.coverArt = coverArt
        self.size = size
        self.contentType = contentType
        self.suffix = suffix
        self.transcodedContentType = transcodedContentType
        self.transcodedSuffix = transcodedSuffix
        self.duration = duration
        self.bitRate = bitRate
        self.samplingRate = samplingRate
        self.channelCount = channelCount
        self.path = path
        self.playCount = playCount
        self.played = played
        self.created = created
        self.starred = starred
        self.userRating = userRating
        self.averageRating = averageRating
        self.bpm = bpm
        self.comment = comment
        self.musicBrainzId = musicBrainzId
        self.isVideo = isVideo
        self.type = type
        self.replayGain = replayGain
        self.kultrStreamUrl = kultrStreamUrl
    }

    enum CodingKeys: String, CodingKey {
        case id, parent, title, album, artist, albumId, artistId, track, discNumber, year, genre, coverArt, size
        case contentType, suffix, transcodedContentType, transcodedSuffix, duration, bitRate, samplingRate
        case channelCount, path, playCount, played, created, starred, userRating, averageRating, bpm, comment
        case musicBrainzId, isVideo, type, replayGain, kultrStreamUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.string(.id), !id.isEmpty else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: c.codingPath, debugDescription: "Song without an id"))
        }
        self.id = id
        parent = c.string(.parent)
        title = c.string(.title) ?? ""
        album = c.string(.album)
        artist = c.string(.artist)
        albumId = c.string(.albumId)
        artistId = c.string(.artistId)
        track = c.int(.track)
        discNumber = c.int(.discNumber)
        year = c.int(.year)
        genre = c.string(.genre)
        coverArt = c.string(.coverArt)
        size = c.int64(.size)
        contentType = c.string(.contentType)
        suffix = c.string(.suffix)
        transcodedContentType = c.string(.transcodedContentType)
        transcodedSuffix = c.string(.transcodedSuffix)
        duration = c.int(.duration)
        bitRate = c.int(.bitRate)
        samplingRate = c.int(.samplingRate)
        channelCount = c.int(.channelCount)
        path = c.string(.path)
        playCount = c.int64(.playCount)
        played = c.string(.played)
        created = c.string(.created)
        starred = c.string(.starred)
        userRating = c.int(.userRating)
        averageRating = c.double(.averageRating)
        bpm = c.int(.bpm)
        comment = c.string(.comment)
        musicBrainzId = c.string(.musicBrainzId)
        isVideo = c.bool(.isVideo)
        type = c.string(.type)
        replayGain = c.object(ReplayGain.self, .replayGain)
        kultrStreamUrl = c.string(.kultrStreamUrl)
    }

    var isStarred: Bool { !(starred ?? "").isEmpty }
    var isRadio: Bool { kultrStreamUrl != nil }

    /** The artwork id to ask the server for: the song's own, else its album's. */
    var artworkId: String? { coverArt ?? albumId }
}

struct Album: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var artist: String?
    var artistId: String?
    var coverArt: String?
    var songCount: Int?
    var duration: Int?
    var playCount: Int64?
    /** When any of its tracks was last played (OpenSubsonic; Navidrome sends it). */
    var played: String?
    var created: String?
    var changed: String?
    var starred: String?
    var year: Int?
    var genre: String?
    var userRating: Int?
    var sortName: String?
    var isCompilation: Bool?
    /** Present on getAlbum, absent on getAlbumList2. */
    var song: [Song]?

    init(
        id: String,
        name: String = "",
        artist: String? = nil,
        artistId: String? = nil,
        coverArt: String? = nil,
        songCount: Int? = nil,
        duration: Int? = nil,
        playCount: Int64? = nil,
        played: String? = nil,
        created: String? = nil,
        changed: String? = nil,
        starred: String? = nil,
        year: Int? = nil,
        genre: String? = nil,
        userRating: Int? = nil,
        sortName: String? = nil,
        isCompilation: Bool? = nil,
        song: [Song]? = nil
    ) {
        self.id = id
        self.name = name
        self.artist = artist
        self.artistId = artistId
        self.coverArt = coverArt
        self.songCount = songCount
        self.duration = duration
        self.playCount = playCount
        self.played = played
        self.created = created
        self.changed = changed
        self.starred = starred
        self.year = year
        self.genre = genre
        self.userRating = userRating
        self.sortName = sortName
        self.isCompilation = isCompilation
        self.song = song
    }

    enum CodingKeys: String, CodingKey {
        case id, name, artist, artistId, coverArt, songCount, duration, playCount, played, created, changed, starred
        case year, genre, userRating, sortName, isCompilation, song
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.string(.id), !id.isEmpty else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: c.codingPath, debugDescription: "Album without an id"))
        }
        self.id = id
        name = c.string(.name) ?? ""
        artist = c.string(.artist)
        artistId = c.string(.artistId)
        coverArt = c.string(.coverArt)
        songCount = c.int(.songCount)
        duration = c.int(.duration)
        playCount = c.int64(.playCount)
        played = c.string(.played)
        created = c.string(.created)
        changed = c.string(.changed)
        starred = c.string(.starred)
        year = c.int(.year)
        genre = c.string(.genre)
        userRating = c.int(.userRating)
        sortName = c.string(.sortName)
        isCompilation = c.bool(.isCompilation)
        song = c.list(Song.self, .song)
    }

    var isStarred: Bool { !(starred ?? "").isEmpty }
}

struct Artist: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var coverArt: String?
    var artistImageUrl: String?
    var albumCount: Int?
    var starred: String?
    var userRating: Int?
    var sortName: String?
    var musicBrainzId: String?
    var album: [Album]?

    init(
        id: String,
        name: String = "",
        coverArt: String? = nil,
        artistImageUrl: String? = nil,
        albumCount: Int? = nil,
        starred: String? = nil,
        userRating: Int? = nil,
        sortName: String? = nil,
        musicBrainzId: String? = nil,
        album: [Album]? = nil
    ) {
        self.id = id
        self.name = name
        self.coverArt = coverArt
        self.artistImageUrl = artistImageUrl
        self.albumCount = albumCount
        self.starred = starred
        self.userRating = userRating
        self.sortName = sortName
        self.musicBrainzId = musicBrainzId
        self.album = album
    }

    enum CodingKeys: String, CodingKey {
        case id, name, coverArt, artistImageUrl, albumCount, starred, userRating, sortName, musicBrainzId, album
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.string(.id), !id.isEmpty else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: c.codingPath, debugDescription: "Artist without an id"))
        }
        self.id = id
        name = c.string(.name) ?? ""
        coverArt = c.string(.coverArt)
        artistImageUrl = c.string(.artistImageUrl)
        albumCount = c.int(.albumCount)
        starred = c.string(.starred)
        userRating = c.int(.userRating)
        sortName = c.string(.sortName)
        musicBrainzId = c.string(.musicBrainzId)
        album = c.list(Album.self, .album)
    }

    var isStarred: Bool { !(starred ?? "").isEmpty }
}

struct ArtistIndex: Decodable, Hashable {
    var name: String
    var artist: [Artist]

    enum CodingKeys: String, CodingKey { case name, artist }

    init(name: String = "", artist: [Artist] = []) {
        self.name = name
        self.artist = artist
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.string(.name) ?? ""
        artist = c.list(Artist.self, .artist) ?? []
    }
}

struct ArtistInfo: Decodable, Hashable {
    var biography: String?
    var musicBrainzId: String?
    var lastFmUrl: String?
    var smallImageUrl: String?
    var mediumImageUrl: String?
    var largeImageUrl: String?
    var similarArtist: [Artist]?

    enum CodingKeys: String, CodingKey {
        case biography, musicBrainzId, lastFmUrl, smallImageUrl, mediumImageUrl, largeImageUrl, similarArtist
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        biography = c.string(.biography)
        musicBrainzId = c.string(.musicBrainzId)
        lastFmUrl = c.string(.lastFmUrl)
        smallImageUrl = c.string(.smallImageUrl)
        mediumImageUrl = c.string(.mediumImageUrl)
        largeImageUrl = c.string(.largeImageUrl)
        similarArtist = c.list(Artist.self, .similarArtist)
    }
}

struct AlbumInfo: Decodable, Hashable {
    var notes: String?
    var lastFmUrl: String?

    enum CodingKeys: String, CodingKey { case notes, lastFmUrl }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notes = c.string(.notes)
        lastFmUrl = c.string(.lastFmUrl)
    }
}

struct Playlist: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var comment: String?
    var owner: String?
    var isPublic: Bool?
    var songCount: Int?
    var duration: Int?
    var created: String?
    var changed: String?
    var coverArt: String?
    var entry: [Song]?

    init(
        id: String,
        name: String = "",
        comment: String? = nil,
        owner: String? = nil,
        isPublic: Bool? = nil,
        songCount: Int? = nil,
        duration: Int? = nil,
        created: String? = nil,
        changed: String? = nil,
        coverArt: String? = nil,
        entry: [Song]? = nil
    ) {
        self.id = id
        self.name = name
        self.comment = comment
        self.owner = owner
        self.isPublic = isPublic
        self.songCount = songCount
        self.duration = duration
        self.created = created
        self.changed = changed
        self.coverArt = coverArt
        self.entry = entry
    }

    enum CodingKeys: String, CodingKey {
        case id, name, comment, owner
        case isPublic = "public"
        case songCount, duration, created, changed, coverArt, entry
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.string(.id), !id.isEmpty else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: c.codingPath, debugDescription: "Playlist without an id"))
        }
        self.id = id
        name = c.string(.name) ?? ""
        comment = c.string(.comment)
        owner = c.string(.owner)
        isPublic = c.bool(.isPublic)
        songCount = c.int(.songCount)
        duration = c.int(.duration)
        created = c.string(.created)
        changed = c.string(.changed)
        coverArt = c.string(.coverArt)
        entry = c.list(Song.self, .entry)
    }
}

struct Genre: Codable, Hashable, Identifiable {
    var value: String
    var songCount: Int?
    var albumCount: Int?

    var id: String { value }

    init(value: String = "", songCount: Int? = nil, albumCount: Int? = nil) {
        self.value = value
        self.songCount = songCount
        self.albumCount = albumCount
    }

    enum CodingKeys: String, CodingKey { case value, songCount, albumCount }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = c.string(.value) ?? ""
        songCount = c.int(.songCount)
        albumCount = c.int(.albumCount)
    }
}

struct ScanStatus: Decodable, Hashable {
    var scanning: Bool
    var count: Int64?
    var folderCount: Int64?
    var lastScan: String?

    init(scanning: Bool = false, count: Int64? = nil, folderCount: Int64? = nil, lastScan: String? = nil) {
        self.scanning = scanning
        self.count = count
        self.folderCount = folderCount
        self.lastScan = lastScan
    }

    enum CodingKeys: String, CodingKey { case scanning, count, folderCount, lastScan }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scanning = c.bool(.scanning) ?? false
        count = c.int64(.count)
        folderCount = c.int64(.folderCount)
        lastScan = c.string(.lastScan)
    }
}

struct SubsonicUser: Decodable, Hashable {
    var username: String
    var email: String?
    var scrobblingEnabled: Bool?
    var adminRole: Bool?
    var streamRole: Bool?
    var downloadRole: Bool?
    var playlistRole: Bool?
    var shareRole: Bool?

    enum CodingKeys: String, CodingKey {
        case username, email, scrobblingEnabled, adminRole, streamRole, downloadRole, playlistRole, shareRole
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        username = c.string(.username) ?? ""
        email = c.string(.email)
        scrobblingEnabled = c.bool(.scrobblingEnabled)
        adminRole = c.bool(.adminRole)
        streamRole = c.bool(.streamRole)
        downloadRole = c.bool(.downloadRole)
        playlistRole = c.bool(.playlistRole)
        shareRole = c.bool(.shareRole)
    }
}

struct RadioStation: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var streamUrl: String
    var homePageUrl: String?

    init(id: String, name: String = "", streamUrl: String = "", homePageUrl: String? = nil) {
        self.id = id
        self.name = name
        self.streamUrl = streamUrl
        self.homePageUrl = homePageUrl
    }

    enum CodingKeys: String, CodingKey { case id, name, streamUrl, homePageUrl }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.string(.id), !id.isEmpty else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: c.codingPath, debugDescription: "Station without an id"))
        }
        self.id = id
        name = c.string(.name) ?? ""
        streamUrl = c.string(.streamUrl) ?? ""
        homePageUrl = c.string(.homePageUrl)
    }

    /** Radio stations are played through the same queue as library tracks. */
    func asSong() -> Song {
        Song(id: "radio:\(id)", title: name, album: homePageUrl, artist: "Internet radio", kultrStreamUrl: streamUrl)
    }
}

struct Lyrics: Decodable, Hashable {
    var artist: String?
    var title: String?
    var value: String?

    init(artist: String? = nil, title: String? = nil, value: String? = nil) {
        self.artist = artist
        self.title = title
        self.value = value
    }

    enum CodingKeys: String, CodingKey { case artist, title, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artist = c.string(.artist)
        title = c.string(.title)
        value = c.string(.value)
    }
}

struct StructuredLyricLine: Decodable, Hashable {
    /** Milliseconds from the start of the track, when synced. */
    var start: Int64?
    var value: String

    init(start: Int64? = nil, value: String = "") {
        self.start = start
        self.value = value
    }

    enum CodingKeys: String, CodingKey { case start, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = c.int64(.start)
        value = c.string(.value) ?? ""
    }
}

struct StructuredLyrics: Decodable, Hashable {
    var lang: String?
    var synced: Bool
    var displayArtist: String?
    var displayTitle: String?
    /** Milliseconds to add to every line's start. */
    var offset: Int64?
    var line: [StructuredLyricLine]?

    init(
        lang: String? = nil,
        synced: Bool = false,
        displayArtist: String? = nil,
        displayTitle: String? = nil,
        offset: Int64? = nil,
        line: [StructuredLyricLine]? = nil
    ) {
        self.lang = lang
        self.synced = synced
        self.displayArtist = displayArtist
        self.displayTitle = displayTitle
        self.offset = offset
        self.line = line
    }

    enum CodingKeys: String, CodingKey { case lang, synced, displayArtist, displayTitle, offset, line }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lang = c.string(.lang)
        synced = c.bool(.synced) ?? false
        displayArtist = c.string(.displayArtist)
        displayTitle = c.string(.displayTitle)
        offset = c.int64(.offset)
        line = c.list(StructuredLyricLine.self, .line)
    }
}

struct SearchResult3: Decodable, Hashable {
    var artist: [Artist]
    var album: [Album]
    var song: [Song]

    init(artist: [Artist] = [], album: [Album] = [], song: [Song] = []) {
        self.artist = artist
        self.album = album
        self.song = song
    }

    enum CodingKeys: String, CodingKey { case artist, album, song }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artist = c.list(Artist.self, .artist) ?? []
        album = c.list(Album.self, .album) ?? []
        song = c.list(Song.self, .song) ?? []
    }
}

struct Starred: Decodable, Hashable {
    var artist: [Artist]
    var album: [Album]
    var song: [Song]

    init(artist: [Artist] = [], album: [Album] = [], song: [Song] = []) {
        self.artist = artist
        self.album = album
        self.song = song
    }

    enum CodingKeys: String, CodingKey { case artist, album, song }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artist = c.list(Artist.self, .artist) ?? []
        album = c.list(Album.self, .album) ?? []
        song = c.list(Song.self, .song) ?? []
    }
}

struct ServerInfo: Decodable, Hashable {
    var version: String?
    var type: String?
    var serverVersion: String?
    var openSubsonic: Bool?

    init(version: String? = nil, type: String? = nil, serverVersion: String? = nil, openSubsonic: Bool? = nil) {
        self.version = version
        self.type = type
        self.serverVersion = serverVersion
        self.openSubsonic = openSubsonic
    }

    enum CodingKeys: String, CodingKey { case version, type, serverVersion, openSubsonic }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = c.string(.version)
        type = c.string(.type)
        serverVersion = c.string(.serverVersion)
        openSubsonic = c.bool(.openSubsonic)
    }

    /** "Navidrome 0.53.3", or whatever best describes the server. */
    var summary: String {
        let name: String
        if let type, let first = type.first {
            name = first.uppercased() + String(type.dropFirst())
        } else {
            name = "Subsonic"
        }
        if let ver = serverVersion ?? version { return "\(name) \(ver)" }
        return name
    }
}

enum AuthMode: String, Codable, Hashable {
    /** md5(password + salt) on every request. The default and the safe choice. */
    case token
    /** Hex-encoded password. Only for reverse proxies that break token auth. */
    case plain
}

struct Credentials: Hashable {
    /** Base URL of the server, no trailing slash. */
    var serverUrl: String
    var username: String
    var password: String
    var authMode: AuthMode = .token
}
