import AVFoundation
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

/** A folder of music on the phone, chosen in the Files folder picker. */
struct LocalFolder: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    /** Lets Kultr open the folder again after a restart (iOS gives access to it and nothing else). */
    var bookmark: Data
}

/**
 * Music on the phone, played without a server.
 *
 * The person chooses one or more folders in the Files picker (on this
 * iPhone, iCloud Drive, a USB drive, another app's storage), which gives
 * Kultr lasting access to those folders and nothing else. A scan walks them,
 * reads each new or changed file's tags, and fills the same kind of library
 * database a server sync fills, as a library of its own ("Music on this
 * phone"). Tracks play straight from their files; favourites, ratings, play
 * counts and playlists are kept on the phone.
 */
@MainActor
@Observable
final class LocalLibrary {
    /** The profile id of the library on the phone (a server profile's id is its address and user). */
    static let profileId = "local"
    static let label = "Music on this phone"
    /** Cover images Kultr made for the library on the phone ("local-art:<name>"). */
    static let artPrefix = "local-art:"

    private(set) var folders: [LocalFolder] = []

    @ObservationIgnored private var opened: [String: URL] = [:]
    private static let foldersKey = "local.folders"

    init() {
        folders = Self.load()
        for folder in folders { _ = open(folder) }
    }

    private static func load() -> [LocalFolder] {
        guard let data = UserDefaults.standard.data(forKey: foldersKey) else { return [] }
        return (try? JSONDecoder().decode([LocalFolder].self, from: data)) ?? []
    }

    private func save(_ list: [LocalFolder]) {
        folders = list
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: Self.foldersKey) }
    }

    /** Keep a folder picked in the Files picker. Returns it, or nil if iOS did not give access to it. */
    func addFolder(_ url: URL) -> LocalFolder? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else { return nil }
        if let existing = folders.first(where: { opened[$0.id]?.standardizedFileURL == url.standardizedFileURL }) { return existing }
        let folder = LocalFolder(id: UUID().uuidString, name: url.lastPathComponent, bookmark: bookmark)
        save(folders + [folder])
        _ = open(folder)
        return folder
    }

    func removeFolder(_ folder: LocalFolder) {
        opened.removeValue(forKey: folder.id)?.stopAccessingSecurityScopedResource()
        save(folders.filter { $0.id != folder.id })
    }

    /** Forget every folder and the covers made for them, for when the library on the phone is removed. */
    func forgetAll() {
        for folder in folders { removeFolder(folder) }
        try? FileManager.default.removeItem(at: Self.artDirectory)
    }

    /**
     * The folder's location, with access to it started (and kept while Kultr
     * runs, so its tracks can play). Nil when it cannot be opened any more.
     */
    func open(_ folder: LocalFolder) -> URL? {
        if let url = opened[folder.id] { return url }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: folder.bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        opened[folder.id] = url
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            save(folders.map { $0.id == folder.id ? LocalFolder(id: folder.id, name: folder.name, bookmark: fresh) : $0 })
        }
        return url
    }

    // ------------------------------------------------------- where things are --

    /** A local track: its id says so. */
    nonisolated static func isLocal(_ song: Song) -> Bool { song.id.hasPrefix(LocalCatalogBuilder.songPrefix) }

    /** Where a local track's file is now, or nil for a server track (or a folder that is gone). */
    func fileURL(_ song: Song) -> URL? {
        guard Self.isLocal(song), let path = song.path, let bar = path.firstIndex(of: "|") else { return nil }
        let folderId = String(path[..<bar])
        let relative = String(path[path.index(after: bar)...])
        guard let folder = folders.first(where: { $0.id == folderId }), let root = open(folder) else { return nil }
        return relative.isEmpty ? root : root.appendingPathComponent(relative)
    }

    nonisolated static var artDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("local-art", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /** The image for a local cover id ("local-art:…"), or nil for a server's cover id. */
    nonisolated static func artURL(_ coverId: String?) -> URL? {
        guard let coverId, coverId.hasPrefix(artPrefix) else { return nil }
        return artDirectory.appendingPathComponent(String(coverId.dropFirst(artPrefix.count)) + ".jpg")
    }

    // -------------------------------------------------------------- scanning --

    /** Scan the folders into [db]. [SyncMode.full] re-reads every file's tags; otherwise only new and changed ones. */
    func scan(into db: LibraryDatabase, mode: SyncMode, onProgress: @escaping @Sendable (SyncProgress) -> Void) async throws -> SyncSummary {
        let roots = folders.map { folder in (folder, open(folder)) }
        return try await Task.detached(priority: .utility) {
            try await LocalScanner(roots: roots, db: db, mode: mode, onProgress: onProgress).run()
        }.value
    }
}

// ------------------------------------------------------------------ scanner --

/** One pass over the music folders, off the main thread. */
private final class LocalScanner: @unchecked Sendable {
    private let roots: [(LocalFolder, URL?)]
    private let db: LibraryDatabase
    private let mode: SyncMode
    private let onProgress: @Sendable (SyncProgress) -> Void
    private var errors: [String] = []
    /** Cover image per folder key, best name first (cover.jpg before folder.jpg and so on). */
    private var covers: [String: (rank: Int, url: URL)] = [:]
    private var waitingForICloud = 0

    private static let audioExtensions: Set<String> = ["mp3", "m4a", "m4b", "mp4", "aac", "alac", "flac", "wav", "wave", "aif", "aiff", "aifc", "caf"]
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "heic"]
    private static let coverNames = ["cover", "folder", "front", "album", "albumart", "artwork", "albumartsmall"]
    private static let coverPixels: CGFloat = 600

    init(roots: [(LocalFolder, URL?)], db: LibraryDatabase, mode: SyncMode, onProgress: @escaping @Sendable (SyncProgress) -> Void) {
        self.roots = roots
        self.db = db
        self.mode = mode
        self.onProgress = onProgress
    }

    private struct Found: Sendable {
        var track: LocalTrack
        var url: URL
    }

    func run() async throws -> SyncSummary {
        let startedAt = Format.nowMs()
        let store = DatabaseLibraryStore(db)
        onProgress(SyncProgress(phase: .connecting, message: "Looking through your folders…", current: 0, total: 1, percent: 0))

        // ------------------------------------------------------------ walk --
        var files: [Found] = []
        var unreadable = 0
        for (folder, root) in roots {
            try Task.checkCancellation()
            guard let root, walk(folder: folder, root: root, into: &files) else {
                unreadable += 1
                errors.append("Kultr can no longer open “\(folder.name)”. Choose it again in Settings → Music on this phone.")
                continue
            }
            onProgress(SyncProgress(phase: .artists, message: "Found \(files.count) tracks…", current: 0, total: 1, percent: 0.05))
        }

        // ------------------------------------------------------------ tags --
        let before = Dictionary(db.allSongs().compactMap { song in song.path.map { ($0, song) } }, uniquingKeysWith: { a, _ in a })
        let previousAlbums = Dictionary(db.albums().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let previousArtists = Dictionary(db.artists().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var tracks: [LocalTrack?] = Array(repeating: nil, count: files.count)
        var toRead: [Int] = []
        for (index, found) in files.enumerated() {
            if mode != .full, let known = before[found.track.path], known.size == found.track.size,
               known.created == Format.iso(found.track.modified) {
                var track = found.track
                track.title = known.title
                track.artist = known.artist
                track.album = known.album
                track.track = known.track
                track.disc = known.discNumber
                track.year = known.year
                track.genre = known.genre
                track.durationMs = known.duration.map { Int64($0) * 1000 }
                track.bitRate = known.bitRate.map { $0 * 1000 }
                track.sampleRate = known.samplingRate
                track.mimeType = known.contentType
                tracks[index] = restoreAlbumArtist(track, albumId: known.albumId, albums: previousAlbums)
            } else {
                toRead.append(index)
            }
        }
        let read = try await readTags(toRead.map { files[$0] })
        for (position, index) in toRead.enumerated() { tracks[index] = read[position] }

        // ------------------------------------------------------- catalogue --
        var folderCovers: [String: String] = [:]
        for (key, cover) in covers {
            try Task.checkCancellation()
            if let id = saveCover(from: cover.url, name: "folder-" + String(md5Hex(key).prefix(16))) { folderCovers[key] = id }
        }
        let known = Dictionary(before.values.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let catalog = LocalCatalogBuilder.build(tracks.compactMap { $0 }, covers: folderCovers) { known[$0] }

        // Albums without a cover image in their folder use the picture in their first track, if any.
        onProgress(SyncProgress(phase: .albums, message: "Finding covers…", current: 0, total: 1, percent: 0.88))
        let urlByPath = Dictionary(files.map { ($0.track.path, $0.url) }, uniquingKeysWith: { a, _ in a })
        var embedded: [String: String] = [:]
        for album in catalog.albums where album.coverArt == nil {
            try Task.checkCancellation()
            guard let path = catalog.songs.first(where: { $0.albumId == album.id })?.path, let url = urlByPath[path] else { continue }
            if let id = embeddedCover(albumId: album.id, track: url) { embedded[album.id] = id }
        }

        // Favourites and ratings of albums and artists belong to the person, not the files.
        let albums: [Album] = catalog.albums.map { album in
            var copy = album
            copy.coverArt = album.coverArt ?? embedded[album.id]
            copy.starred = previousAlbums[album.id]?.starred
            copy.userRating = previousAlbums[album.id]?.userRating
            return copy
        }
        let coverOf = Dictionary(albums.map { ($0.id, $0.coverArt) }, uniquingKeysWith: { a, _ in a })
        let songs: [Song] = catalog.songs.map { song in
            var copy = song
            copy.coverArt = song.albumId.flatMap { coverOf[$0] ?? nil } ?? song.coverArt
            return copy
        }
        let artists: [Artist] = catalog.artists.map { artist in
            var copy = artist
            copy.coverArt = albums.first { $0.artistId == artist.id && $0.coverArt != nil }?.coverArt
            copy.starred = previousArtists[artist.id]?.starred
            copy.userRating = previousArtists[artist.id]?.userRating
            return copy
        }

        // ----------------------------------------------------------- store --
        onProgress(SyncProgress(phase: .cleanup, message: "Saving your library…", current: 1, total: 1, percent: 0.95))
        try await store.putArtists(artists)
        try await store.putAlbums(albums)
        try await store.replaceAlbumSongs(Dictionary(grouping: songs) { $0.albumId ?? "" })
        try await store.replaceGenres(catalog.genres)
        var albumsRemoved = 0
        var songsRemoved = 0
        // A folder that could not be opened (a drive taken out) must not empty the library.
        if unreadable == 0 {
            let albumIds = Set(albums.map { $0.id })
            albumsRemoved = try await store.deleteAlbumsNotIn(albumIds)
            _ = try await store.deleteArtistsNotIn(Set(artists.map { $0.id }))
            songsRemoved = try await store.deleteSongsOutsideAlbums(albumIds)
        }

        let counts = try await store.counts()
        var state = try await store.syncState()
        state.lastFullSync = mode == .full ? startedAt : (state.lastFullSync ?? startedAt)
        state.lastCheck = startedAt
        state.counts = counts
        state.serverType = "local"
        state.serverVersion = nil
        state.newestAlbumCreated = albums.compactMap { $0.created }.max()
        try await store.setSyncState(state)
        onProgress(SyncProgress(phase: .done, message: "Library up to date", current: 1, total: 1, percent: 1))

        if waitingForICloud > 0 {
            errors.append("\(Format.count(waitingForICloud, "file")) in iCloud \(waitingForICloud == 1 ? "is" : "are") still downloading to this iPhone. Scan again in a little while.")
        }
        let added = albums.filter { previousAlbums[$0.id] == nil }.count
        let readIds = Set(read.compactMap { $0 }.map { LocalCatalogBuilder.songId($0.path) })
        let changedAlbums = Set(songs.filter { readIds.contains($0.id) }.compactMap { $0.albumId })
        let updated = changedAlbums.filter { previousAlbums[$0] != nil }.count
        return SyncSummary(
            mode: mode,
            startedAt: startedAt,
            finishedAt: Format.nowMs(),
            counts: counts,
            albumsAdded: added,
            albumsUpdated: updated,
            albumsRemoved: albumsRemoved,
            songsRemoved: songsRemoved,
            upToDate: added == 0 && updated == 0 && albumsRemoved == 0 && songsRemoved == 0,
            errors: errors
        )
    }

    /**
     * The album artist is not kept per song, but grouping needs it. An
     * unchanged song's album was grouped by album artist exactly when its id
     * is the one that grouping gives, and then the album's artist is it.
     */
    private func restoreAlbumArtist(_ track: LocalTrack, albumId: String?, albums: [String: Album]) -> LocalTrack {
        guard let albumId, let artist = albums[albumId]?.artist else { return track }
        var copy = track
        if LocalCatalogBuilder.albumId(LocalCatalogBuilder.albumName(track), artist, track.folderKey) == albumId {
            copy.albumArtist = artist
        }
        return copy
    }

    /** Every audio file under [root]; false if the folder cannot be read at all. */
    private func walk(folder: LocalFolder, root: URL, into out: inout [Found]) -> Bool {
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey, .ubiquitousItemDownloadingStatusKey]
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        guard (try? base.checkResourceIsReachable()) == true,
              let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants])
        else { return false }
        let baseComponents = base.pathComponents
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if name.hasPrefix(".") { enumerator.skipDescendants() }
                continue
            }
            // A file iCloud has not brought down yet ("Song.mp3" shown as ".Song.mp3.icloud" on older iOS).
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                let real = url.deletingLastPathComponent().appendingPathComponent(String(name.dropFirst().dropLast(7)))
                if Self.audioExtensions.contains(real.pathExtension.lowercased()) {
                    try? FileManager.default.startDownloadingUbiquitousItem(at: real)
                    waitingForICloud += 1
                }
                continue
            }
            if name.hasPrefix(".") { continue }
            let ext = url.pathExtension.lowercased()
            let full = url.resolvingSymlinksInPath().standardizedFileURL
            let components = full.pathComponents
            guard components.count > baseComponents.count, Array(components.prefix(baseComponents.count)) == baseComponents else { continue }
            let relativeParts = Array(components.dropFirst(baseComponents.count))
            let directoryParts = relativeParts.dropLast()
            let folderKey = folder.id + "|" + directoryParts.joined(separator: "/")
            if Self.imageExtensions.contains(ext) {
                let stem = (name as NSString).deletingPathExtension.lowercased()
                if let rank = Self.coverNames.firstIndex(of: stem), rank < (covers[folderKey]?.rank ?? Int.max) {
                    covers[folderKey] = (rank, url)
                }
                continue
            }
            guard Self.audioExtensions.contains(ext) else { continue }
            if let status = values?.ubiquitousItemDownloadingStatus, status != .current {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                waitingForICloud += 1
                continue
            }
            let modified = values?.contentModificationDate.map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0
            out.append(Found(
                track: LocalTrack(
                    path: folder.id + "|" + relativeParts.joined(separator: "/"),
                    fileName: name,
                    folderKey: folderKey,
                    folderName: directoryParts.last ?? folder.name,
                    // Whole seconds: that is what the library keeps, so an unchanged file compares equal.
                    modified: modified / 1000 * 1000,
                    size: Int64(values?.fileSize ?? 0),
                    mimeType: UTType(filenameExtension: ext)?.preferredMIMEType
                ),
                url: url
            ))
        }
        return true
    }

    /** Tags for these files, four at a time. */
    private func readTags(_ files: [Found]) async throws -> [LocalTrack?] {
        var results: [LocalTrack?] = Array(repeating: nil, count: files.count)
        let total = files.count
        try await withThrowingTaskGroup(of: (Int, LocalTrack).self) { group in
            var next = 0
            var done = 0
            while next < min(4, files.count) {
                let index = next
                let found = files[index]
                next += 1
                group.addTask { (index, await Self.readTags(found)) }
            }
            while let (index, track) = try await group.next() {
                try Task.checkCancellation()
                results[index] = track
                done += 1
                if done % 10 == 0 || done == total {
                    onProgress(SyncProgress(
                        phase: .songs,
                        message: "Reading tags… \(done) of \(total)",
                        current: done,
                        total: total,
                        percent: 0.1 + 0.75 * Double(done) / Double(max(1, total))
                    ))
                }
                if next < files.count {
                    let nextIndex = next
                    let found = files[nextIndex]
                    next += 1
                    group.addTask { (nextIndex, await Self.readTags(found)) }
                }
            }
        }
        return results
    }

    private static func readTags(_ found: Found) async -> LocalTrack {
        var track = found.track
        if let source = FileSource(url: found.url) {
            track = track.with(AudioTagReader.read(source, fileExtension: found.url.pathExtension))
        }
        // Formats whose length is not in their headers: ask AVFoundation.
        if track.durationMs == nil {
            let asset = AVURLAsset(url: found.url)
            if let duration = try? await asset.load(.duration), duration.isNumeric, duration.seconds > 0 {
                track.durationMs = Int64(duration.seconds * 1000)
                if track.size > 0 { track.bitRate = Int(Double(track.size) * 8 / duration.seconds) }
            }
        }
        return track
    }

    /** The picture inside a track, saved small as the album's cover; nil if it has none. */
    private func embeddedCover(albumId: String, track: URL) -> String? {
        let name = "embedded-" + String(md5Hex(albumId).prefix(16))
        let file = LocalLibrary.artDirectory.appendingPathComponent(name + ".jpg")
        let none = LocalLibrary.artDirectory.appendingPathComponent(name + ".none")
        if mode != .full {
            if FileManager.default.fileExists(atPath: file.path) { return LocalLibrary.artPrefix + name }
            if FileManager.default.fileExists(atPath: none.path) { return nil }
        }
        guard let source = FileSource(url: track),
              let picture = AudioTagReader.read(source, fileExtension: track.pathExtension, picture: true).picture,
              let id = saveCover(data: picture, name: name)
        else {
            FileManager.default.createFile(atPath: none.path, contents: nil)
            return nil
        }
        try? FileManager.default.removeItem(at: none)
        return id
    }

    /** A folder's cover image, made small and kept by Kultr (the folder might not stay readable). */
    private func saveCover(from url: URL, name: String) -> String? {
        let file = LocalLibrary.artDirectory.appendingPathComponent(name + ".jpg")
        if mode != .full,
           let made = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
           let changed = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
           made >= changed {
            return LocalLibrary.artPrefix + name
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return saveCover(data: data, name: name)
    }

    private func saveCover(data: Data, name: String) -> String? {
        let file = LocalLibrary.artDirectory.appendingPathComponent(name + ".jpg")
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.coverPixels,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return LocalLibrary.artPrefix + name
    }
}
