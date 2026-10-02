import Foundation
import UIKit

/**
 * What is playing, as the app last told the widget: written by the app into
 * the shared App Group container, read by the widget. Compiled into both.
 */
struct NowPlayingSnapshot: Codable, Equatable {
    var songId: String
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    /** Where the track was, and when; with [isPlaying] the widget runs its own progress bar. */
    var positionMs: Int64
    var durationMs: Int64
    var at: Date
    /** The artwork's colour, as 0xRRGGBB. */
    var accent: UInt32
    var hasArtwork: Bool
    /** The next songs in the queue, for the large widgets; nil from versions before 1.2.1. */
    var upNext: [UpNextSong]?
    /** How many songs follow in all (more than [upNext] holds). */
    var upNextCount: Int?
    var shuffle: Bool?
    /** "off", "all" or "one". */
    var repeatMode: String?

    /** When the track started, as if it had played without a pause. */
    var startedAt: Date { at.addingTimeInterval(-Double(positionMs) / 1000) }
    var endsAt: Date { startedAt.addingTimeInterval(Double(max(durationMs, 1)) / 1000) }
    var progress: Double { durationMs > 0 ? min(1, max(0, Double(positionMs) / Double(durationMs))) : 0 }
}

/** A song waiting in the queue: what the large widgets list under "Up next". */
struct UpNextSong: Codable, Equatable, Identifiable {
    var songId: String
    var title: String
    var artist: String
    /** Its place in the queue, for jumping to it. */
    var index: Int
    var hasArtwork: Bool

    var id: String { "\(index):\(songId)" }
}

/**
 * The App Group container the app and its widget share.
 *
 * Kultr is sideloaded, and the tool that signs it decides the group's real
 * name (SideStore and AltStore add your team id to it). So the name is read
 * from what the signing left behind, in order: the `ALTAppGroups` list
 * AltStore and SideStore write into Info.plist, then the provisioning profile
 * inside the app, and only then the name Kultr asks for.
 */
enum SharedStore {
    static let requestedGroup = "group.app.kultr.ios"

    static let container: URL? = {
        for group in candidateGroups() {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
                return url
            }
        }
        return nil
    }()

    private static func candidateGroups() -> [String] {
        var groups: [String] = []
        if let listed = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] {
            groups += listed
        }
        groups += profileGroups()
        groups.append(requestedGroup)
        var seen = Set<String>()
        return groups.filter { seen.insert($0).inserted }
    }

    /** The app groups in embedded.mobileprovision, preferring ones that look like Kultr's. */
    private static func profileGroups() -> [String] {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return [] }
        let plist = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let root = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
              let entitlements = root["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String]
        else { return [] }
        return groups.sorted { a, _ in a.contains("kultr") }
    }

    private static var snapshotURL: URL? { container?.appendingPathComponent("now-playing.json") }
    private static var artworkURL: URL? { container?.appendingPathComponent("now-playing-artwork.jpg") }

    private static var queueArtFolder: URL? { container?.appendingPathComponent("queue-art", isDirectory: true) }

    /** A song id as a file name. */
    private static func artName(_ songId: String) -> String {
        let safe = songId.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" }
        return String(safe.prefix(80)) + ".jpg"
    }

    /** The small cover of a song waiting in the queue. */
    static func queueArtwork(_ songId: String) -> UIImage? {
        guard let url = queueArtFolder?.appendingPathComponent(artName(songId)), let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func hasQueueArtwork(_ songId: String) -> Bool {
        guard let url = queueArtFolder?.appendingPathComponent(artName(songId)) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func writeQueueArtwork(_ songId: String, _ jpeg: Data) {
        guard let folder = queueArtFolder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? jpeg.write(to: folder.appendingPathComponent(artName(songId)), options: .atomic)
    }

    /** Removes the covers of songs no longer waiting. */
    static func keepQueueArtwork(_ songIds: Set<String>) {
        guard let folder = queueArtFolder,
              let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
        else { return }
        let keep = Set(songIds.map(artName))
        for file in files where !keep.contains(file) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
        }
    }

    static func read() -> NowPlayingSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(NowPlayingSnapshot.self, from: data)
    }

    static func artwork() -> UIImage? {
        guard let url = artworkURL, let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /** Returns false when there is no shared container (the signing tool gave Kultr no App Group). */
    @discardableResult
    static func write(_ snapshot: NowPlayingSnapshot?, artwork: Data?) -> Bool {
        guard let snapshotURL, let artworkURL else { return false }
        if let artwork {
            try? artwork.write(to: artworkURL, options: .atomic)
        } else if snapshot?.hasArtwork == false {
            try? FileManager.default.removeItem(at: artworkURL)
        }
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: snapshotURL, options: .atomic)
        } else if snapshot == nil {
            try? FileManager.default.removeItem(at: snapshotURL)
        }
        return true
    }
}
