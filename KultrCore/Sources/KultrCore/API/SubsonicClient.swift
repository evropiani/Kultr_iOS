import CryptoKit
import Foundation

/** Protocol version we speak. 1.16.1 is what Navidrome implements. */
let API_VERSION = "1.16.1"
let CLIENT_NAME = "Kultr"

struct SubsonicError: LocalizedError, Equatable {
    let code: Int
    let message: String

    var errorDescription: String? { message }
}

struct NetworkError: LocalizedError, Equatable {
    let message: String

    var errorDescription: String? { message }
}

/** Human-readable explanations for the Subsonic error codes Navidrome uses. */
func describeError(_ error: Error) -> String {
    if let err = error as? SubsonicError {
        switch err.code {
        case 0: return err.message.trimmingCharacters(in: .whitespaces).isEmpty ? "The server reported a generic error." : err.message
        case 10: return "The server is missing a required parameter."
        case 20: return "Your server is too old for this client."
        case 30: return "This client is too old for your server."
        case 40: return "Wrong username or password."
        case 41: return "Token authentication is disabled on this server. Switch to “Plain password” in the advanced options (and use HTTPS!)."
        case 50: return "Your account is not allowed to do that."
        case 60: return "This feature needs a Subsonic Premium subscription (not applicable to Navidrome)."
        case 70: return "Not found."
        default: return err.message.trimmingCharacters(in: .whitespaces).isEmpty ? "Server error \(err.code)." : err.message
        }
    }
    if let err = error as? NetworkError { return err.message }
    if let err = error as? URLError {
        switch err.code {
        case .cannotFindHost, .dnsLookupFailed:
            return "Could not find that server. Check the address."
        case .cannotConnectToHost, .networkConnectionLost:
            return "Could not connect to the server. Is it running, and reachable from this phone?"
        case .notConnectedToInternet:
            return "This phone is not connected to the internet."
        case .timedOut:
            return "The server took too long to answer."
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected,
             .clientCertificateRequired:
            return "A secure connection could not be made: \(err.localizedDescription)"
        case .appTransportSecurityRequiresSecureConnection:
            return "This address needs HTTPS."
        case .cancelled:
            return "Cancelled."
        default:
            return err.localizedDescription
        }
    }
    if error is CancellationError { return "Cancelled." }
    if let err = error as? LocalizedError, let text = err.errorDescription { return text }
    return (error as NSError).localizedDescription
}

/**
 * Add a scheme when the person typed a bare host, and drop trailing slashes.
 * A bare address gets https — plain http only when asked for explicitly.
 */
func normalizeServerUrl(_ raw: String) -> String {
    var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    while trimmed.hasSuffix("/") { trimmed.removeLast() }
    if trimmed.isEmpty { return "" }
    if trimmed.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) != nil { return trimmed }
    return "https://" + trimmed
}

/** True when [url] parses as an http(s) address with a host. */
func isValidServerUrl(_ url: String) -> Bool {
    SubsonicClient.parseBase(url) != nil
}

private let saltAlphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")

func randomSalt(length: Int = 12) -> String {
    var generator = SystemRandomNumberGenerator()
    return String((0..<length).map { _ in saltAlphabet.randomElement(using: &generator)! })
}

func md5Hex(_ input: String) -> String {
    let digest = Insecure.MD5.hash(data: Data(input.utf8))
    return hexEncode(Array(digest))
}

func hexEncode(_ bytes: [UInt8]) -> String {
    let hex = Array("0123456789abcdef")
    var out = ""
    out.reserveCapacity(bytes.count * 2)
    for byte in bytes {
        out.append(hex[Int(byte >> 4)])
        out.append(hex[Int(byte & 0x0f)])
    }
    return out
}

enum AlbumListType: String {
    case random
    case newest
    case highest
    case frequent
    case recent
    case alphabeticalByName
    case alphabeticalByArtist
    case starred
    case byYear
    case byGenre
}

extension CodingUserInfoKey {
    static let subsonicPath = CodingUserInfoKey(rawValue: "kultr.subsonicPath")!
}

/**
 * The whole response in one pass: the envelope's status and error, and the
 * payload found by walking the key path given in the decoder's user info.
 */
struct SubsonicEnvelope<T: Decodable>: Decodable {
    let hasEnvelope: Bool
    let failed: Bool
    let errorCode: Int
    let errorMessage: String?
    let payload: T?

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: AnyKey.self)
        let envelopeKey = AnyKey("subsonic-response")
        guard root.contains(envelopeKey),
              let body = try? root.nestedContainer(keyedBy: AnyKey.self, forKey: envelopeKey)
        else {
            hasEnvelope = false
            failed = false
            errorCode = 0
            errorMessage = nil
            payload = nil
            return
        }
        hasEnvelope = true
        failed = body.string("status") == "failed"
        if failed {
            let error = try? body.nestedContainer(keyedBy: AnyKey.self, forKey: "error")
            errorCode = error?.int("code") ?? 0
            errorMessage = error?.string("message")
            payload = nil
            return
        }
        errorCode = 0
        errorMessage = nil
        let path = decoder.userInfo[.subsonicPath] as? [String] ?? []
        if path.isEmpty {
            payload = try? T(from: root.superDecoder(forKey: envelopeKey))
            return
        }
        var container = body
        for key in path.dropLast() {
            guard let next = try? container.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey(key)) else {
                payload = nil
                return
            }
            container = next
        }
        let last = AnyKey(path[path.count - 1])
        if container.contains(last), (try? container.decodeNil(forKey: last)) != true {
            payload = try? T(from: container.superDecoder(forKey: last))
        } else {
            payload = nil
        }
    }
}

/**
 * A Subsonic API client. Every call is an async function that throws
 * [SubsonicError] for API errors and [NetworkError] for transport ones.
 */
final class SubsonicClient: @unchecked Sendable {
    let credentials: Credentials
    var baseUrl: String { credentials.serverUrl }

    private let session: URLSession
    private let userAgent: String
    private let base: URLComponents?

    /**
     * One salt for the lifetime of this client, used for URLs something else
     * holds on to (the player, the image cache). A URL that changed on every
     * call would defeat every cache between us and the server. Pass a value
     * derived from the profile to keep them identical across launches.
     */
    private let stableSalt: String
    private let stableToken: String

    init(credentials: Credentials, session: URLSession = .shared, stableSalt: String? = nil, userAgent: String = "Kultr-iOS") {
        var creds = credentials
        creds.serverUrl = normalizeServerUrl(credentials.serverUrl)
        self.credentials = creds
        self.session = session
        self.userAgent = userAgent
        let salt: String
        if let stableSalt, stableSalt.count >= 6 {
            salt = stableSalt
        } else {
            salt = randomSalt()
        }
        self.stableSalt = salt
        self.stableToken = md5Hex(creds.password + salt)
        self.base = SubsonicClient.parseBase(creds.serverUrl)
    }

    static func parseBase(_ url: String) -> URLComponents? {
        guard let components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else { return nil }
        return components
    }

    private func authParams(stable: Bool) -> [(String, String)] {
        var params: [(String, String)] = [
            ("u", credentials.username),
            ("v", API_VERSION),
            ("c", CLIENT_NAME),
            ("f", "json"),
        ]
        if credentials.authMode == .plain {
            params.append(("p", "enc:" + hexEncode(Array(credentials.password.utf8))))
            return params
        }
        if stable {
            params.append(("s", stableSalt))
            params.append(("t", stableToken))
        } else {
            let salt = randomSalt()
            params.append(("s", salt))
            params.append(("t", md5Hex(credentials.password + salt)))
        }
        return params
    }

    private static let queryAllowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    private static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? text
    }

    /**
     * Build a fully-qualified, authenticated URL for any endpoint. Nil values,
     * empty strings and empty lists are left out; lists repeat the key.
     */
    func buildUrl(_ endpoint: String, _ params: [(String, Any?)] = [], stable: Bool = false) throws -> URL {
        guard var components = base else {
            throw NetworkError(message: "“\(baseUrl)” is not a valid server address.")
        }
        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        components.percentEncodedPath = path + "/rest/" + endpoint
        var pairs: [(String, String)] = authParams(stable: stable)
        for (key, value) in params {
            guard let value else { continue }
            if let list = value as? [String] {
                pairs += list.filter { !$0.isEmpty }.map { (key, $0) }
            } else if let list = value as? [Int] {
                pairs += list.map { (key, String($0)) }
            } else if let flag = value as? Bool {
                pairs.append((key, flag ? "true" : "false"))
            } else {
                let text = "\(value)"
                if !text.isEmpty { pairs.append((key, text)) }
            }
        }
        components.percentEncodedQuery = pairs
            .map { SubsonicClient.encode($0.0) + "=" + SubsonicClient.encode($0.1) }
            .joined(separator: "&")
        guard let url = components.url else {
            throw NetworkError(message: "“\(baseUrl)” is not a valid server address.")
        }
        return url
    }

    private func perform<T: Decodable>(
        _ endpoint: String,
        _ params: [(String, Any?)] = [],
        path: [String],
        as type: T.Type,
        timeout: TimeInterval = 30
    ) async throws -> T? {
        let url = try buildUrl(endpoint, params)
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            if error.code == .timedOut { throw NetworkError(message: "The server did not answer within \(Int(timeout))s.") }
            throw NetworkError(message: describeError(error))
        }
        if Task.isCancelled { throw CancellationError() }
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError(message: "The server sent no HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let reason = HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw NetworkError(message: "Server responded with HTTP \(http.statusCode) \(reason).")
        }
        let decoder = JSONDecoder()
        decoder.userInfo[.subsonicPath] = path
        let envelope: SubsonicEnvelope<T>
        do {
            envelope = try decoder.decode(SubsonicEnvelope<T>.self, from: data)
        } catch {
            throw NetworkError(message: "The server sent something that is not a Subsonic JSON response. Is the address pointing at Navidrome?")
        }
        guard envelope.hasEnvelope else {
            throw NetworkError(message: "Malformed response: no “subsonic-response” envelope.")
        }
        if envelope.failed {
            throw SubsonicError(code: envelope.errorCode, message: envelope.errorMessage ?? "Unknown error")
        }
        return envelope.payload
    }

    private func list<T: Decodable>(
        _ endpoint: String,
        _ params: [(String, Any?)] = [],
        _ outer: String,
        _ inner: String,
        of type: T.Type,
        timeout: TimeInterval = 30
    ) async throws -> [T] {
        try await perform(endpoint, params, path: [outer, inner], as: LossyList<T>.self, timeout: timeout)?.items ?? []
    }

    private func call(_ endpoint: String, _ params: [(String, Any?)] = []) async throws {
        _ = try await perform(endpoint, params, path: [], as: EmptyPayload.self)
    }

    // ------------------------------------------------------------ system --

    func ping() async throws -> ServerInfo {
        try await perform("ping", path: [], as: ServerInfo.self, timeout: 15) ?? ServerInfo()
    }

    func getUser(_ username: String? = nil) async throws -> SubsonicUser? {
        try await perform("getUser", [("username", username ?? credentials.username)], path: ["user"], as: SubsonicUser.self)
    }

    func getScanStatus() async throws -> ScanStatus {
        try await perform("getScanStatus", path: ["scanStatus"], as: ScanStatus.self) ?? ScanStatus()
    }

    func startScan(fullScan: Bool = false) async throws -> ScanStatus {
        try await perform("startScan", [("fullScan", fullScan)], path: ["scanStatus"], as: ScanStatus.self) ?? ScanStatus(scanning: true)
    }

    // ---------------------------------------------------------- browsing --

    func getArtists() async throws -> [Artist] {
        let indexes = try await list("getArtists", [], "artists", "index", of: ArtistIndex.self, timeout: 60)
        return indexes.flatMap { $0.artist }
    }

    func getArtist(_ id: String) async throws -> Artist? {
        try await perform("getArtist", [("id", id)], path: ["artist"], as: Artist.self)
    }

    func getArtistInfo2(_ id: String, count: Int = 20) async throws -> ArtistInfo? {
        try await perform(
            "getArtistInfo2",
            [("id", id), ("count", count), ("includeNotPresent", false)],
            path: ["artistInfo2"],
            as: ArtistInfo.self
        )
    }

    func getAlbum(_ id: String) async throws -> Album? {
        try await perform("getAlbum", [("id", id)], path: ["album"], as: Album.self)
    }

    func getAlbumInfo2(_ id: String) async throws -> AlbumInfo? {
        try await perform("getAlbumInfo2", [("id", id)], path: ["albumInfo"], as: AlbumInfo.self)
    }

    func getSong(_ id: String) async throws -> Song? {
        try await perform("getSong", [("id", id)], path: ["song"], as: Song.self)
    }

    func getAlbumList2(
        _ type: AlbumListType,
        size: Int = 100,
        offset: Int = 0,
        fromYear: Int? = nil,
        toYear: Int? = nil,
        genre: String? = nil
    ) async throws -> [Album] {
        try await list(
            "getAlbumList2",
            [
                ("type", type.rawValue),
                ("size", size),
                ("offset", offset),
                ("fromYear", fromYear),
                ("toYear", toYear),
                ("genre", genre),
            ],
            "albumList2",
            "album",
            of: Album.self,
            timeout: 60
        )
    }

    func getGenres() async throws -> [Genre] {
        try await list("getGenres", [], "genres", "genre", of: Genre.self)
    }

    func getRandomSongs(size: Int = 50, genre: String? = nil, fromYear: Int? = nil, toYear: Int? = nil) async throws -> [Song] {
        try await list(
            "getRandomSongs",
            [("size", size), ("genre", genre), ("fromYear", fromYear), ("toYear", toYear)],
            "randomSongs",
            "song",
            of: Song.self
        )
    }

    func getSongsByGenre(_ genre: String, count: Int = 200, offset: Int = 0) async throws -> [Song] {
        try await list("getSongsByGenre", [("genre", genre), ("count", count), ("offset", offset)], "songsByGenre", "song", of: Song.self)
    }

    func getStarred2() async throws -> Starred {
        try await perform("getStarred2", path: ["starred2"], as: Starred.self, timeout: 60) ?? Starred()
    }

    func search3(
        _ query: String,
        artistCount: Int = 20,
        albumCount: Int = 20,
        songCount: Int = 40,
        artistOffset: Int = 0,
        albumOffset: Int = 0,
        songOffset: Int = 0
    ) async throws -> SearchResult3 {
        try await perform(
            "search3",
            [
                ("query", query),
                ("artistCount", artistCount),
                ("artistOffset", artistOffset),
                ("albumCount", albumCount),
                ("albumOffset", albumOffset),
                ("songCount", songCount),
                ("songOffset", songOffset),
            ],
            path: ["searchResult3"],
            as: SearchResult3.self,
            timeout: 60
        ) ?? SearchResult3()
    }

    func getSimilarSongs2(_ id: String, count: Int = 50) async throws -> [Song] {
        try await list("getSimilarSongs2", [("id", id), ("count", count)], "similarSongs2", "song", of: Song.self)
    }

    func getTopSongs(_ artist: String, count: Int = 50) async throws -> [Song] {
        try await list("getTopSongs", [("artist", artist), ("count", count)], "topSongs", "song", of: Song.self)
    }

    // --------------------------------------------------------- playlists --

    func getPlaylists() async throws -> [Playlist] {
        try await list("getPlaylists", [], "playlists", "playlist", of: Playlist.self)
    }

    func getPlaylist(_ id: String) async throws -> Playlist? {
        try await perform("getPlaylist", [("id", id)], path: ["playlist"], as: Playlist.self, timeout: 60)
    }

    @discardableResult
    func createPlaylist(name: String, songIds: [String] = []) async throws -> Playlist? {
        try await perform("createPlaylist", [("name", name), ("songId", songIds)], path: ["playlist"], as: Playlist.self)
    }

    func updatePlaylist(
        _ playlistId: String,
        name: String? = nil,
        comment: String? = nil,
        isPublic: Bool? = nil,
        songIdToAdd: [String] = [],
        songIndexToRemove: [Int] = []
    ) async throws {
        try await call(
            "updatePlaylist",
            [
                ("playlistId", playlistId),
                ("name", name),
                ("comment", comment),
                ("public", isPublic),
                ("songIdToAdd", songIdToAdd),
                ("songIndexToRemove", songIndexToRemove),
            ]
        )
    }

    func deletePlaylist(_ id: String) async throws {
        try await call("deletePlaylist", [("id", id)])
    }

    // ------------------------------------------------------- annotations --

    func star(id: String? = nil, albumId: String? = nil, artistId: String? = nil) async throws {
        try await call("star", [("id", id), ("albumId", albumId), ("artistId", artistId)])
    }

    func unstar(id: String? = nil, albumId: String? = nil, artistId: String? = nil) async throws {
        try await call("unstar", [("id", id), ("albumId", albumId), ("artistId", artistId)])
    }

    func setRating(_ id: String, rating: Int) async throws {
        try await call("setRating", [("id", id), ("rating", min(5, max(0, rating)))])
    }

    func scrobble(_ id: String, submission: Bool, timeMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) async throws {
        try await call("scrobble", [("id", id), ("submission", submission), ("time", timeMs)])
    }

    // ------------------------------------------------------------- media --

    /** Streaming URL for the player. Stable for the lifetime of this client. */
    func streamUrl(_ id: String, maxBitRate: Int? = nil, format: String? = nil) -> URL? {
        let bitrate: Int? = (maxBitRate ?? 0) > 0 ? maxBitRate : nil
        let fmt: String? = (format?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) ? nil : format
        return try? buildUrl(
            "stream",
            [("id", id), ("maxBitRate", bitrate), ("format", fmt), ("estimateContentLength", true)],
            stable: true
        )
    }

    /** Original-file download URL (never transcoded). */
    func downloadUrl(_ id: String) -> URL? {
        try? buildUrl("download", [("id", id)], stable: true)
    }

    /** Artwork URL. Stable, so the image cache keeps working. */
    func coverArtUrl(_ coverArtId: String?, size: Int? = nil) -> URL? {
        guard let coverArtId, !coverArtId.isEmpty else { return nil }
        return try? buildUrl("getCoverArt", [("id", coverArtId), ("size", size)], stable: true)
    }

    func getLyrics(artist: String?, title: String?) async throws -> Lyrics? {
        try await perform("getLyrics", [("artist", artist), ("title", title)], path: ["lyrics"], as: Lyrics.self)
    }

    /** OpenSubsonic extension; Navidrome supports it and it can return synced lyrics. */
    func getLyricsBySongId(_ id: String) async throws -> [StructuredLyrics] {
        try await list("getLyricsBySongId", [("id", id)], "lyricsList", "structuredLyrics", of: StructuredLyrics.self)
    }

    func getInternetRadioStations() async throws -> [RadioStation] {
        try await list("getInternetRadioStations", [], "internetRadioStations", "internetRadioStation", of: RadioStation.self)
    }

    func getNowPlaying() async throws -> [Song] {
        try await list("getNowPlaying", [], "nowPlaying", "entry", of: Song.self)
    }
}
