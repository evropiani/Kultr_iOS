import Foundation

/*
 * The local mirror of the server's library. One database per server profile,
 * so switching servers never mixes two libraries. The schema matches the
 * Android app's Room database table for table.
 */

/** SQLite allows 999 bound variables on old builds; stay well under it. */
let SQL_CHUNK = 500

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

struct PlaylistRow: Hashable {
    let playlist: Playlist
    /** Song ids in playlist order. Empty when contents were not synced. */
    let entryIds: [String]
    let position: Int
}

struct HistoryEntry: Hashable, Identifiable {
    var id: Int64 = 0
    var songId: String
    var playedAt: Int64
    /** Seconds actually listened to. */
    var seconds: Int
    var completed: Bool
    var source: String
    /** Whether the server has been told (scrobbles made offline are sent later). */
    var submitted: Bool
}

enum DownloadState {
    static let queued = "queued"
    static let done = "done"
    static let failed = "failed"
}

struct DownloadRow: Hashable {
    var songId: String
    var state: String
    /** File name of the stored copy inside the profile's offline folder, once downloaded. */
    var path: String?
    var size: Int64
    var contentType: String?
    var requestedAt: Int64
    var savedAt: Int64?
    var error: String?
}

struct DownloadUsage: Hashable {
    var count: Int
    var bytes: Int64
}

enum LibraryChange: Hashable {
    case library, history, downloads, analysis
}

final class LibraryDatabase: @unchecked Sendable {
    private static let schemaVersion = 1

    private let db: SQLiteConnection

    /** Called after every write, from whatever thread made it. */
    var onChange: ((Set<LibraryChange>) -> Void)?

    static func fileName(profileId: String) -> String {
        "library-\(md5Hex(profileId).prefix(16)).sqlite"
    }

    init(path: String) throws {
        db = try SQLiteConnection(path: path)
        try migrate()
    }

    func close() {
        db.close()
    }

    private func changed(_ changes: Set<LibraryChange>) {
        onChange?(changes)
    }

    // ---------------------------------------------------------------- schema --

    private func migrate() throws {
        let version = try db.scalarInt("PRAGMA user_version")
        if version == Self.schemaVersion { return }
        // The mirror can always be rebuilt from the server.
        try db.executeScript(
            """
            DROP TABLE IF EXISTS songs; DROP TABLE IF EXISTS albums; DROP TABLE IF EXISTS artists;
            DROP TABLE IF EXISTS playlists; DROP TABLE IF EXISTS genres; DROP TABLE IF EXISTS analysis;
            DROP TABLE IF EXISTS history; DROP TABLE IF EXISTS downloads; DROP TABLE IF EXISTS meta;
            CREATE TABLE songs (
                id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL, sortTitle TEXT NOT NULL, album TEXT, artist TEXT,
                albumId TEXT, artistId TEXT, track INTEGER, discNumber INTEGER, year INTEGER, genre TEXT, coverArt TEXT,
                size INTEGER, contentType TEXT, suffix TEXT, duration INTEGER, bitRate INTEGER, samplingRate INTEGER,
                channelCount INTEGER, path TEXT, playCount INTEGER, played TEXT, created TEXT, starred TEXT,
                userRating INTEGER, bpm INTEGER, comment TEXT, trackGain REAL, albumGain REAL, trackPeak REAL, albumPeak REAL
            );
            CREATE INDEX idx_songs_albumId ON songs(albumId);
            CREATE INDEX idx_songs_artistId ON songs(artistId);
            CREATE INDEX idx_songs_genre ON songs(genre);
            CREATE INDEX idx_songs_starred ON songs(starred);
            CREATE INDEX idx_songs_created ON songs(created);
            CREATE INDEX idx_songs_sortTitle ON songs(sortTitle);
            CREATE TABLE albums (
                id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, sortName TEXT NOT NULL, artist TEXT, artistId TEXT,
                coverArt TEXT, songCount INTEGER, duration INTEGER, playCount INTEGER, created TEXT, changed TEXT,
                starred TEXT, year INTEGER, genre TEXT, userRating INTEGER, isCompilation INTEGER
            );
            CREATE INDEX idx_albums_artistId ON albums(artistId);
            CREATE INDEX idx_albums_starred ON albums(starred);
            CREATE INDEX idx_albums_created ON albums(created);
            CREATE INDEX idx_albums_sortName ON albums(sortName);
            CREATE INDEX idx_albums_genre ON albums(genre);
            CREATE TABLE artists (
                id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, sortName TEXT NOT NULL, coverArt TEXT,
                artistImageUrl TEXT, albumCount INTEGER, starred TEXT, userRating INTEGER
            );
            CREATE INDEX idx_artists_sortName ON artists(sortName);
            CREATE INDEX idx_artists_starred ON artists(starred);
            CREATE TABLE playlists (
                id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, comment TEXT, owner TEXT, isPublic INTEGER,
                songCount INTEGER, duration INTEGER, created TEXT, changed TEXT, coverArt TEXT,
                entryIds TEXT NOT NULL, position INTEGER NOT NULL
            );
            CREATE TABLE genres (value TEXT PRIMARY KEY NOT NULL, songCount INTEGER, albumCount INTEGER);
            CREATE TABLE analysis (
                songId TEXT PRIMARY KEY NOT NULL, version INTEGER NOT NULL, analysedAt INTEGER NOT NULL,
                bpmSource TEXT NOT NULL, duration REAL NOT NULL, bpm REAL NOT NULL, bpmConfidence REAL NOT NULL,
                beatOffset REAL NOT NULL, downbeatOffset REAL NOT NULL, outroDownbeat REAL NOT NULL,
                musicalKey INTEGER NOT NULL, keyName TEXT NOT NULL, mode TEXT NOT NULL, keyConfidence REAL NOT NULL,
                camelot TEXT NOT NULL, energy REAL NOT NULL, brightness REAL NOT NULL, peak REAL NOT NULL,
                introEnd REAL NOT NULL, outroStart REAL NOT NULL
            );
            CREATE TABLE history (
                id INTEGER PRIMARY KEY AUTOINCREMENT, songId TEXT NOT NULL, playedAt INTEGER NOT NULL,
                seconds INTEGER NOT NULL, completed INTEGER NOT NULL, source TEXT NOT NULL, submitted INTEGER NOT NULL
            );
            CREATE INDEX idx_history_songId ON history(songId);
            CREATE INDEX idx_history_playedAt ON history(playedAt);
            CREATE TABLE downloads (
                songId TEXT PRIMARY KEY NOT NULL, state TEXT NOT NULL, path TEXT, size INTEGER NOT NULL,
                contentType TEXT, requestedAt INTEGER NOT NULL, savedAt INTEGER, error TEXT
            );
            CREATE INDEX idx_downloads_state ON downloads(state);
            CREATE TABLE meta (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
            PRAGMA user_version = \(Self.schemaVersion);
            """
        )
    }

    // --------------------------------------------------------------- mapping --

    private static let songInsert =
        "INSERT OR REPLACE INTO songs (id, title, sortTitle, album, artist, albumId, artistId, track, discNumber, year, genre, " +
        "coverArt, size, contentType, suffix, duration, bitRate, samplingRate, channelCount, path, playCount, played, created, " +
        "starred, userRating, bpm, comment, trackGain, albumGain, trackPeak, albumPeak) " +
        "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"

    private static func songArgs(_ s: Song) -> [SQLiteBindable] {
        [
            s.id, s.title, Format.sortKey(s.title), s.album, s.artist, s.albumId, s.artistId, s.track, s.discNumber,
            s.year, s.genre, s.coverArt, s.size, s.contentType, s.suffix, s.duration, s.bitRate, s.samplingRate,
            s.channelCount, s.path, s.playCount, s.played, s.created, s.starred, s.userRating, s.bpm, s.comment,
            s.replayGain?.trackGain, s.replayGain?.albumGain, s.replayGain?.trackPeak, s.replayGain?.albumPeak,
        ]
    }

    static func song(_ r: SQLiteRow) -> Song {
        let trackGain = r.double(27)
        let albumGain = r.double(28)
        return Song(
            id: r.text(0),
            title: r.text(1),
            album: r.string(3),
            artist: r.string(4),
            albumId: r.string(5),
            artistId: r.string(6),
            track: r.int(7),
            discNumber: r.int(8),
            year: r.int(9),
            genre: r.string(10),
            coverArt: r.string(11),
            size: r.int64(12),
            contentType: r.string(13),
            suffix: r.string(14),
            duration: r.int(15),
            bitRate: r.int(16),
            samplingRate: r.int(17),
            channelCount: r.int(18),
            path: r.string(19),
            playCount: r.int64(20),
            played: r.string(21),
            created: r.string(22),
            starred: r.string(23),
            userRating: r.int(24),
            bpm: r.int(25),
            comment: r.string(26),
            replayGain: trackGain != nil || albumGain != nil
                ? ReplayGain(trackGain: trackGain, albumGain: albumGain, trackPeak: r.double(29), albumPeak: r.double(30))
                : nil
        )
    }

    private static let albumInsert =
        "INSERT OR REPLACE INTO albums (id, name, sortName, artist, artistId, coverArt, songCount, duration, playCount, created, " +
        "changed, starred, year, genre, userRating, isCompilation) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"

    private static func albumArgs(_ a: Album) -> [SQLiteBindable] {
        [
            a.id, a.name, Format.sortKey(a.sortName ?? a.name), a.artist, a.artistId, a.coverArt, a.songCount, a.duration,
            a.playCount, a.created, a.changed, a.starred, a.year, a.genre, a.userRating, a.isCompilation,
        ]
    }

    static func album(_ r: SQLiteRow) -> Album {
        Album(
            id: r.text(0),
            name: r.text(1),
            artist: r.string(3),
            artistId: r.string(4),
            coverArt: r.string(5),
            songCount: r.int(6),
            duration: r.int(7),
            playCount: r.int64(8),
            created: r.string(9),
            changed: r.string(10),
            starred: r.string(11),
            year: r.int(12),
            genre: r.string(13),
            userRating: r.int(14),
            isCompilation: r.bool(15)
        )
    }

    private static let artistInsert =
        "INSERT OR REPLACE INTO artists (id, name, sortName, coverArt, artistImageUrl, albumCount, starred, userRating) " +
        "VALUES (?,?,?,?,?,?,?,?)"

    private static func artistArgs(_ a: Artist) -> [SQLiteBindable] {
        [a.id, a.name, Format.sortKey(a.sortName ?? a.name), a.coverArt, a.artistImageUrl, a.albumCount, a.starred, a.userRating]
    }

    static func artist(_ r: SQLiteRow) -> Artist {
        Artist(
            id: r.text(0),
            name: r.text(1),
            coverArt: r.string(3),
            artistImageUrl: r.string(4),
            albumCount: r.int(5),
            starred: r.string(6),
            userRating: r.int(7)
        )
    }

    private static let playlistInsert =
        "INSERT OR REPLACE INTO playlists (id, name, comment, owner, isPublic, songCount, duration, created, changed, coverArt, " +
        "entryIds, position) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)"

    static func encodeIds(_ ids: [String]) -> String {
        guard let data = try? JSONEncoder().encode(ids), let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }

    static func decodeIds(_ text: String) -> [String] {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return [] }
        return (try? JSONDecoder().decode([String].self, from: Data(text.utf8))) ?? []
    }

    private static func playlistArgs(_ p: Playlist, position: Int, entryIds: [String]) -> [SQLiteBindable] {
        [
            p.id, p.name, p.comment, p.owner, p.isPublic, p.songCount, p.duration, p.created, p.changed, p.coverArt,
            encodeIds(entryIds), position,
        ]
    }

    static func playlistRow(_ r: SQLiteRow) -> PlaylistRow {
        PlaylistRow(
            playlist: Playlist(
                id: r.text(0),
                name: r.text(1),
                comment: r.string(2),
                owner: r.string(3),
                isPublic: r.bool(4),
                songCount: r.int(5),
                duration: r.int(6),
                created: r.string(7),
                changed: r.string(8),
                coverArt: r.string(9)
            ),
            entryIds: decodeIds(r.text(10)),
            position: r.int(11) ?? 0
        )
    }

    static func analysis(_ r: SQLiteRow) -> TrackAnalysis {
        TrackAnalysis(
            songId: r.text(0),
            version: r.int(1) ?? 0,
            analysedAt: r.int64(2) ?? 0,
            bpmSource: BpmSource(rawValue: r.text(3)) ?? .dsp,
            duration: r.double(4) ?? 0,
            bpm: r.double(5) ?? 0,
            bpmConfidence: r.double(6) ?? 0,
            beatOffset: r.double(7) ?? 0,
            downbeatOffset: r.double(8) ?? 0,
            outroDownbeat: r.double(9) ?? 0,
            key: r.int(10) ?? 0,
            keyName: r.text(11),
            mode: KeyMode(rawValue: r.text(12)) ?? .major,
            keyConfidence: r.double(13) ?? 0,
            camelot: r.text(14),
            energy: r.double(15) ?? 0,
            brightness: r.double(16) ?? 0,
            peak: r.double(17) ?? 0,
            introEnd: r.double(18) ?? 0,
            outroStart: r.double(19) ?? 0
        )
    }

    static func history(_ r: SQLiteRow) -> HistoryEntry {
        HistoryEntry(
            id: r.int64(0) ?? 0,
            songId: r.text(1),
            playedAt: r.int64(2) ?? 0,
            seconds: r.int(3) ?? 0,
            completed: r.bool(4) ?? false,
            source: r.text(5),
            submitted: r.bool(6) ?? false
        )
    }

    static func download(_ r: SQLiteRow) -> DownloadRow {
        DownloadRow(
            songId: r.text(0),
            state: r.text(1),
            path: r.string(2),
            size: r.int64(3) ?? 0,
            contentType: r.string(4),
            requestedAt: r.int64(5) ?? 0,
            savedAt: r.int64(6),
            error: r.string(7)
        )
    }

    private func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ",")
    }

    private func read<T>(_ sql: String, _ args: [SQLiteBindable] = [], _ map: (SQLiteRow) -> T) -> [T] {
        (try? db.query(sql, args, map)) ?? []
    }

    /** Rows whose [column] is in [ids], chunked to stay under the variable limit. */
    private func readIn<T>(_ prefix: String, _ ids: [String], _ map: (SQLiteRow) -> T) -> [T] {
        var out: [T] = []
        for chunk in Array(Set(ids)).chunked(SQL_CHUNK) {
            out += read("\(prefix) IN (\(placeholders(chunk.count)))", chunk, map)
        }
        return out
    }

    private func deleteIn(_ prefix: String, _ ids: [String]) throws {
        for chunk in ids.chunked(SQL_CHUNK) {
            try db.execute("\(prefix) IN (\(placeholders(chunk.count)))", chunk)
        }
    }

    // ------------------------------------------------------------- library writes --

    func upsertSongs(_ songs: [Song]) throws {
        try db.executeMany(Self.songInsert, songs.map(Self.songArgs))
        changed([.library])
    }

    func upsertAlbums(_ albums: [Album]) throws {
        try db.executeMany(Self.albumInsert, albums.map(Self.albumArgs))
        changed([.library])
    }

    func upsertArtists(_ artists: [Artist]) throws {
        try db.executeMany(Self.artistInsert, artists.map(Self.artistArgs))
        changed([.library])
    }

    /** Replace every playlist; entry ids come from each playlist's `entry`. */
    func replacePlaylists(_ playlists: [Playlist]) throws {
        try db.transaction {
            try db.execute("DELETE FROM playlists")
            try db.executeMany(
                Self.playlistInsert,
                playlists.enumerated().map { pair -> [SQLiteBindable] in
                    let ids = (pair.element.entry ?? []).map { song in song.id }
                    return Self.playlistArgs(pair.element, position: pair.offset, entryIds: ids)
                }
            )
        }
        changed([.library])
    }

    func upsertPlaylist(_ playlist: Playlist, position: Int, entryIds: [String]) throws {
        try db.execute(Self.playlistInsert, Self.playlistArgs(playlist, position: position, entryIds: entryIds))
        changed([.library])
    }

    func replaceGenres(_ genres: [Genre]) throws {
        try db.transaction {
            try db.execute("DELETE FROM genres")
            try db.executeMany(
                "INSERT OR REPLACE INTO genres (value, songCount, albumCount) VALUES (?,?,?)",
                genres.map { [$0.value, $0.songCount, $0.albumCount] as [SQLiteBindable] }
            )
        }
        changed([.library])
    }

    func replaceAlbumSongs(_ songsByAlbum: [String: [Song]]) throws {
        try db.transaction {
            for (albumId, songs) in songsByAlbum {
                let keep = Set(songs.map { $0.id })
                let stale = read("SELECT id FROM songs WHERE albumId = ?", [albumId]) { $0.text(0) }.filter { !keep.contains($0) }
                try deleteIn("DELETE FROM songs WHERE id", stale)
            }
            try db.executeMany(Self.songInsert, songsByAlbum.values.flatMap { $0 }.map(Self.songArgs))
        }
        changed([.library])
    }

    func deleteSongs(_ ids: [String]) throws {
        try deleteIn("DELETE FROM songs WHERE id", ids)
        changed([.library])
    }

    func deleteAlbums(_ ids: [String]) throws {
        try deleteIn("DELETE FROM albums WHERE id", ids)
        changed([.library])
    }

    func deleteArtists(_ ids: [String]) throws {
        try deleteIn("DELETE FROM artists WHERE id", ids)
        changed([.library])
    }

    func albumIds() -> [String] { read("SELECT id FROM albums") { $0.text(0) } }
    func artistIds() -> [String] { read("SELECT id FROM artists") { $0.text(0) } }

    func songAlbumPairs() -> [(id: String, albumId: String?)] {
        read("SELECT id, albumId FROM songs") { (id: $0.text(0), albumId: $0.string(1)) }
    }

    func albumStamps() -> [String: AlbumStamp] {
        var out: [String: AlbumStamp] = [:]
        for row in read("SELECT id, songCount, changed, duration FROM albums", [], { r in
            (r.text(0), AlbumStamp(songCount: r.int(1), changed: r.string(2), duration: r.int(3)))
        }) {
            out[row.0] = row.1
        }
        return out
    }

    func setSongStarred(_ id: String, _ starred: String?) throws {
        try db.execute("UPDATE songs SET starred = ? WHERE id = ?", [starred, id])
        changed([.library])
    }

    func setSongsStarred(_ ids: [String], _ starred: String?) throws {
        try db.transaction {
            for id in ids { try db.execute("UPDATE songs SET starred = ? WHERE id = ?", [starred, id]) }
        }
        changed([.library])
    }

    func setAlbumStarred(_ id: String, _ starred: String?) throws {
        try db.execute("UPDATE albums SET starred = ? WHERE id = ?", [starred, id])
        changed([.library])
    }

    func setArtistStarred(_ id: String, _ starred: String?) throws {
        try db.execute("UPDATE artists SET starred = ? WHERE id = ?", [starred, id])
        changed([.library])
    }

    func setSongRating(_ id: String, _ rating: Int) throws {
        try db.execute("UPDATE songs SET userRating = ? WHERE id = ?", [rating, id])
        changed([.library])
    }

    func bumpPlayCount(_ id: String, played: String) throws {
        try db.execute("UPDATE songs SET playCount = COALESCE(playCount, 0) + 1, played = ? WHERE id = ?", [played, id])
        changed([.library])
    }

    func clearLibrary() throws {
        try db.transaction {
            try db.executeScript("DELETE FROM songs; DELETE FROM albums; DELETE FROM artists; DELETE FROM playlists; DELETE FROM genres;")
        }
        changed([.library])
    }

    // -------------------------------------------------------------- library reads --

    func counts() -> LibraryCounts {
        read(
            "SELECT (SELECT COUNT(*) FROM artists), (SELECT COUNT(*) FROM albums), (SELECT COUNT(*) FROM songs), " +
                "(SELECT COUNT(*) FROM playlists), (SELECT COUNT(*) FROM genres)"
        ) { r in
            LibraryCounts(artists: r.int(0) ?? 0, albums: r.int(1) ?? 0, songs: r.int(2) ?? 0, playlists: r.int(3) ?? 0, genres: r.int(4) ?? 0)
        }.first ?? LibraryCounts()
    }

    func albums() -> [Album] { read("SELECT * FROM albums ORDER BY sortName", [], Self.album) }
    func artists() -> [Artist] { read("SELECT * FROM artists ORDER BY sortName", [], Self.artist) }
    func songs() -> [Song] { read("SELECT * FROM songs ORDER BY sortTitle", [], Self.song) }
    func allSongs() -> [Song] { read("SELECT * FROM songs", [], Self.song) }
    func playlists() -> [PlaylistRow] { read("SELECT * FROM playlists ORDER BY position", [], Self.playlistRow) }

    func genres() -> [Genre] {
        read("SELECT value, songCount, albumCount FROM genres ORDER BY songCount DESC") { r in
            Genre(value: r.text(0), songCount: r.int(1), albumCount: r.int(2))
        }
    }

    func song(_ id: String) -> Song? { read("SELECT * FROM songs WHERE id = ?", [id], Self.song).first }
    func songs(ids: [String]) -> [Song] { readIn("SELECT * FROM songs WHERE id", ids, Self.song) }
    func album(_ id: String) -> Album? { read("SELECT * FROM albums WHERE id = ?", [id], Self.album).first }
    func artist(_ id: String) -> Artist? { read("SELECT * FROM artists WHERE id = ?", [id], Self.artist).first }
    func playlist(_ id: String) -> PlaylistRow? { read("SELECT * FROM playlists WHERE id = ?", [id], Self.playlistRow).first }

    func songsOfAlbum(_ albumId: String) -> [Song] {
        read("SELECT * FROM songs WHERE albumId = ? ORDER BY COALESCE(discNumber, 1), COALESCE(track, 0), sortTitle", [albumId], Self.song)
    }

    func songsOfArtist(_ artistId: String) -> [Song] {
        read(
            "SELECT * FROM songs WHERE artistId = ? ORDER BY COALESCE(year, 0) DESC, album, COALESCE(discNumber, 1), COALESCE(track, 0)",
            [artistId],
            Self.song
        )
    }

    func albumsOfArtist(_ artistId: String) -> [Album] {
        read("SELECT * FROM albums WHERE artistId = ? ORDER BY COALESCE(year, 0) DESC, sortName", [artistId], Self.album)
    }

    func songsOfGenre(_ genre: String) -> [Song] {
        read("SELECT * FROM songs WHERE genre = ? ORDER BY artist, album, COALESCE(discNumber, 1), COALESCE(track, 0)", [genre], Self.song)
    }

    func albumsOfGenre(_ genre: String) -> [Album] {
        read("SELECT * FROM albums WHERE genre = ? ORDER BY sortName", [genre], Self.album)
    }

    func starredSongs() -> [Song] {
        read("SELECT * FROM songs WHERE starred IS NOT NULL AND starred != '' ORDER BY starred DESC", [], Self.song)
    }

    func starredAlbums() -> [Album] {
        read("SELECT * FROM albums WHERE starred IS NOT NULL AND starred != '' ORDER BY starred DESC", [], Self.album)
    }

    func starredArtists() -> [Artist] {
        read("SELECT * FROM artists WHERE starred IS NOT NULL AND starred != '' ORDER BY starred DESC", [], Self.artist)
    }

    func recentlyAdded(_ limit: Int) -> [Album] {
        read("SELECT * FROM albums ORDER BY created DESC LIMIT ?", [limit], Self.album)
    }

    func mostPlayedSongs(_ limit: Int) -> [Song] {
        read("SELECT * FROM songs WHERE playCount > 0 ORDER BY playCount DESC LIMIT ?", [limit], Self.song)
    }

    func mostPlayedAlbums(_ limit: Int) -> [Album] {
        read("SELECT * FROM albums WHERE playCount > 0 ORDER BY playCount DESC LIMIT ?", [limit], Self.album)
    }

    func mostPlayedArtists(_ limit: Int) -> [Artist] {
        read(
            "SELECT artists.* FROM artists JOIN (SELECT artistId, SUM(COALESCE(playCount, 0)) AS plays FROM songs " +
                "GROUP BY artistId) p ON p.artistId = artists.id WHERE p.plays > 0 ORDER BY p.plays DESC LIMIT ?",
            [limit],
            Self.artist
        )
    }

    func randomSongs(_ limit: Int) -> [Song] { read("SELECT * FROM songs ORDER BY RANDOM() LIMIT ?", [limit], Self.song) }
    func randomAlbums(_ limit: Int) -> [Album] { read("SELECT * FROM albums ORDER BY RANDOM() LIMIT ?", [limit], Self.album) }
    func randomArtists(_ limit: Int) -> [Artist] { read("SELECT * FROM artists ORDER BY RANDOM() LIMIT ?", [limit], Self.artist) }

    func randomSongsOfGenre(_ genre: String, _ limit: Int) -> [Song] {
        read("SELECT * FROM songs WHERE genre = ? ORDER BY RANDOM() LIMIT ?", [genre, limit], Self.song)
    }

    func searchSongs(_ pattern: String, _ prefix: String, _ limit: Int) -> [Song] {
        read(
            "SELECT * FROM songs WHERE title LIKE ?1 OR artist LIKE ?1 OR album LIKE ?1 " +
                "ORDER BY CASE WHEN title LIKE ?2 THEN 0 ELSE 1 END, COALESCE(playCount, 0) DESC LIMIT ?3",
            [pattern, prefix, limit],
            Self.song
        )
    }

    func searchAlbums(_ pattern: String, _ prefix: String, _ limit: Int) -> [Album] {
        read(
            "SELECT * FROM albums WHERE name LIKE ?1 OR artist LIKE ?1 " +
                "ORDER BY CASE WHEN name LIKE ?2 THEN 0 ELSE 1 END, sortName LIMIT ?3",
            [pattern, prefix, limit],
            Self.album
        )
    }

    func searchArtists(_ pattern: String, _ prefix: String, _ limit: Int) -> [Artist] {
        read(
            "SELECT * FROM artists WHERE name LIKE ?1 ORDER BY CASE WHEN name LIKE ?2 THEN 0 ELSE 1 END, sortName LIMIT ?3",
            [pattern, prefix, limit],
            Self.artist
        )
    }

    // ---------------------------------------------------------------- analysis --

    func analysis(_ songId: String) -> TrackAnalysis? {
        read("SELECT * FROM analysis WHERE songId = ?", [songId], Self.analysis).first
    }

    func analyses(_ ids: [String]) -> [TrackAnalysis] {
        readIn("SELECT * FROM analysis WHERE songId", ids, Self.analysis)
    }

    func putAnalysis(_ a: TrackAnalysis) throws {
        try db.execute(
            "INSERT OR REPLACE INTO analysis VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            [
                a.songId, a.version, a.analysedAt, a.bpmSource.rawValue, a.duration, a.bpm, a.bpmConfidence, a.beatOffset,
                a.downbeatOffset, a.outroDownbeat, a.key, a.keyName, a.mode.rawValue, a.keyConfidence, a.camelot,
                a.energy, a.brightness, a.peak, a.introEnd, a.outroStart,
            ]
        )
        changed([.analysis])
    }

    func analysisCount(version: Int) -> Int {
        (try? db.scalarInt("SELECT COUNT(*) FROM analysis WHERE version = ?", [version])) ?? 0
    }

    func missingAnalysis(version: Int, maxSeconds: Int, limit: Int) -> [Song] {
        read(
            "SELECT songs.* FROM songs LEFT JOIN analysis ON analysis.songId = songs.id " +
                "WHERE (analysis.songId IS NULL OR analysis.version != ?) AND COALESCE(songs.duration, 0) BETWEEN 1 AND ? LIMIT ?",
            [version, maxSeconds, limit],
            Self.song
        )
    }

    func missingAnalysisCount(version: Int, maxSeconds: Int) -> Int {
        (try? db.scalarInt(
            "SELECT COUNT(*) FROM songs LEFT JOIN analysis ON analysis.songId = songs.id " +
                "WHERE (analysis.songId IS NULL OR analysis.version != ?) AND COALESCE(songs.duration, 0) BETWEEN 1 AND ?",
            [version, maxSeconds]
        )) ?? 0
    }

    func clearAnalysis() throws {
        try db.execute("DELETE FROM analysis")
        changed([.analysis])
    }

    // ----------------------------------------------------------------- history --

    @discardableResult
    func insertHistory(_ entry: HistoryEntry) throws -> Int64 {
        let id: Int64 = try db.transaction {
            try db.execute(
                "INSERT INTO history (songId, playedAt, seconds, completed, source, submitted) VALUES (?,?,?,?,?,?)",
                [entry.songId, entry.playedAt, entry.seconds, entry.completed, entry.source, entry.submitted]
            )
            return db.lastInsertRowId
        }
        changed([.history])
        return id
    }

    func recentHistory(_ limit: Int) -> [HistoryEntry] {
        read("SELECT * FROM history ORDER BY playedAt DESC LIMIT ?", [limit], Self.history)
    }

    func unsubmittedHistory(_ limit: Int) -> [HistoryEntry] {
        read("SELECT * FROM history WHERE submitted = 0 ORDER BY playedAt LIMIT ?", [limit], Self.history)
    }

    func markSubmitted(_ id: Int64) throws {
        try db.execute("UPDATE history SET submitted = 1 WHERE id = ?", [id])
    }

    func clearHistory() throws {
        try db.execute("DELETE FROM history")
        changed([.history])
    }

    // --------------------------------------------------------------- downloads --

    private static let downloadInsert =
        "INSERT OR REPLACE INTO downloads (songId, state, path, size, contentType, requestedAt, savedAt, error) VALUES (?,?,?,?,?,?,?,?)"

    func upsertDownloads(_ rows: [DownloadRow]) throws {
        try db.executeMany(
            Self.downloadInsert,
            rows.map { [$0.songId, $0.state, $0.path, $0.size, $0.contentType, $0.requestedAt, $0.savedAt, $0.error] as [SQLiteBindable] }
        )
        changed([.downloads])
    }

    func download(_ songId: String) -> DownloadRow? {
        read("SELECT * FROM downloads WHERE songId = ?", [songId], Self.download).first
    }

    func downloads(_ ids: [String]) -> [DownloadRow] {
        readIn("SELECT * FROM downloads WHERE songId", ids, Self.download)
    }

    func doneDownloads() -> [DownloadRow] {
        read("SELECT * FROM downloads WHERE state = 'done' ORDER BY savedAt DESC", [], Self.download)
    }

    func queuedDownloads(_ limit: Int) -> [DownloadRow] {
        read("SELECT * FROM downloads WHERE state = 'queued' ORDER BY requestedAt LIMIT ?", [limit], Self.download)
    }

    func queuedCount() -> Int {
        (try? db.scalarInt("SELECT COUNT(*) FROM downloads WHERE state = 'queued'")) ?? 0
    }

    func failedDownloads() -> [DownloadRow] {
        read("SELECT * FROM downloads WHERE state = 'failed' ORDER BY requestedAt", [], Self.download)
    }

    @discardableResult
    func requeueFailed(now: Int64) throws -> Int {
        let count = try db.execute("UPDATE downloads SET state = 'queued', error = NULL, requestedAt = ? WHERE state = 'failed'", [now])
        changed([.downloads])
        return count
    }

    func downloadUsage() -> DownloadUsage {
        read("SELECT COUNT(*), COALESCE(SUM(size), 0) FROM downloads WHERE state = 'done'") { r in
            DownloadUsage(count: r.int(0) ?? 0, bytes: r.int64(1) ?? 0)
        }.first ?? DownloadUsage(count: 0, bytes: 0)
    }

    func deleteDownloads(_ ids: [String]) throws {
        try deleteIn("DELETE FROM downloads WHERE songId", ids)
        changed([.downloads])
    }

    func clearQueuedDownloads() throws {
        try db.execute("DELETE FROM downloads WHERE state = 'queued'")
        changed([.downloads])
    }

    func clearFailedDownloads() throws {
        try db.execute("DELETE FROM downloads WHERE state = 'failed'")
        changed([.downloads])
    }

    // -------------------------------------------------------------------- meta --

    func meta(_ key: String) -> String? {
        read("SELECT value FROM meta WHERE key = ?", [key]) { $0.text(0) }.first
    }

    func putMeta(_ key: String, _ value: String) throws {
        try db.execute("INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)", [key, value])
        changed([.library])
    }

    private static let syncStateKey = "syncState"

    func syncState() -> SyncState {
        guard let text = meta(Self.syncStateKey),
              let state = try? JSONDecoder().decode(SyncState.self, from: Data(text.utf8))
        else { return SyncState() }
        return state
    }

    func setSyncState(_ state: SyncState) throws {
        let data = try JSONEncoder().encode(state)
        try putMeta(Self.syncStateKey, String(data: data, encoding: .utf8) ?? "{}")
    }
}

/** The core sync engine's view of the SQLite mirror. */
final class DatabaseLibraryStore: LibraryStore {
    private let db: LibraryDatabase

    init(_ db: LibraryDatabase) {
        self.db = db
    }

    func albumStamps() async throws -> [String: AlbumStamp] { db.albumStamps() }

    func putArtists(_ artists: [Artist]) async throws {
        for chunk in artists.chunked(SQL_CHUNK) { try db.upsertArtists(chunk) }
    }

    func putAlbums(_ albums: [Album]) async throws {
        for chunk in albums.chunked(SQL_CHUNK) { try db.upsertAlbums(chunk) }
    }

    func replaceAlbumSongs(_ songsByAlbum: [String: [Song]]) async throws {
        try db.replaceAlbumSongs(songsByAlbum)
    }

    func replacePlaylists(_ playlists: [Playlist]) async throws {
        try db.replacePlaylists(playlists)
    }

    func replaceGenres(_ genres: [Genre]) async throws { try db.replaceGenres(genres) }

    func deleteAlbumsNotIn(_ keep: Set<String>) async throws -> Int {
        let gone = db.albumIds().filter { !keep.contains($0) }
        try db.deleteAlbums(gone)
        return gone.count
    }

    func deleteArtistsNotIn(_ keep: Set<String>) async throws -> Int {
        let gone = db.artistIds().filter { !keep.contains($0) }
        try db.deleteArtists(gone)
        return gone.count
    }

    func deleteSongsOutsideAlbums(_ albumIds: Set<String>) async throws -> Int {
        let gone = db.songAlbumPairs().filter { $0.albumId == nil || !albumIds.contains($0.albumId!) }.map { $0.id }
        try db.deleteSongs(gone)
        return gone.count
    }

    func counts() async throws -> LibraryCounts { db.counts() }
    func syncState() async throws -> SyncState { db.syncState() }
    func setSyncState(_ state: SyncState) async throws { try db.setSyncState(state) }
}
