import Foundation

/** What a music file's tags say. Everything is optional; files without tags have none of it. */
struct AudioTags: Hashable, Sendable {
    var title: String?
    var artist: String?
    var albumArtist: String?
    var album: String?
    var track: Int?
    var disc: Int?
    var year: Int?
    var genre: String?
    var durationMs: Int64?
    var sampleRate: Int?
    /** The cover picture inside the file (front cover if marked), when asked for. */
    var picture: Data?

    init(
        title: String? = nil, artist: String? = nil, albumArtist: String? = nil, album: String? = nil,
        track: Int? = nil, disc: Int? = nil, year: Int? = nil, genre: String? = nil,
        durationMs: Int64? = nil, sampleRate: Int? = nil, picture: Data? = nil
    ) {
        self.title = title
        self.artist = artist
        self.albumArtist = albumArtist
        self.album = album
        self.track = track
        self.disc = disc
        self.year = year
        self.genre = genre
        self.durationMs = durationMs
        self.sampleRate = sampleRate
        self.picture = picture
    }

    /** Fills what this has not got from [other]. */
    mutating func fill(from other: AudioTags) {
        title = title ?? other.title
        artist = artist ?? other.artist
        albumArtist = albumArtist ?? other.albumArtist
        album = album ?? other.album
        track = track ?? other.track
        disc = disc ?? other.disc
        year = year ?? other.year
        genre = genre ?? other.genre
        durationMs = durationMs ?? other.durationMs
        sampleRate = sampleRate ?? other.sampleRate
        picture = picture ?? other.picture
    }
}

/** Random access to a file's bytes, so a tag reader only reads what it needs. */
protocol ByteSource {
    var size: Int64 { get }
    /** Up to [count] bytes from [offset]; fewer at the end of the file. */
    func read(_ offset: Int64, _ count: Int) -> Data
}

/** A whole file in memory (for tests, and small files). */
struct DataSource: ByteSource {
    let data: Data
    var size: Int64 { Int64(data.count) }

    func read(_ offset: Int64, _ count: Int) -> Data {
        guard offset >= 0, offset < size, count > 0 else { return Data() }
        let start = data.startIndex + Int(offset)
        let end = min(data.endIndex, start + count)
        return Data(data[start..<end])
    }
}

/** A file on disk, read a piece at a time. */
final class FileSource: ByteSource {
    private let handle: FileHandle
    let size: Int64

    init?(url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        self.handle = handle
        size = Int64((try? handle.seekToEnd()) ?? 0)
    }

    deinit { try? handle.close() }

    func read(_ offset: Int64, _ count: Int) -> Data {
        guard offset >= 0, offset < size, count > 0 else { return Data() }
        do {
            try handle.seek(toOffset: UInt64(offset))
            return try handle.read(upToCount: count) ?? Data()
        } catch {
            return Data()
        }
    }
}

/**
 * Reads the tags of the files an iPhone can play: ID3 (MP3, and ID3 chunks
 * before other formats), FLAC's Vorbis comments and pictures, and MP4/M4A
 * (AAC, ALAC) item lists, plus each format's length where it says it.
 * Pure Swift on purpose: AVFoundation does not read FLAC comments, and this
 * can be tested without a device.
 */
enum AudioTagReader {
    static func read(_ source: ByteSource, fileExtension: String, picture wantPicture: Bool = false) -> AudioTags {
        var tags = AudioTags()
        var offset: Int64 = 0
        // ID3v2 comes first in an MP3, and sometimes before a FLAC stream as well.
        while let (id3, length) = readID3v2(source, at: offset, wantPicture: wantPicture) {
            tags.fill(from: id3)
            offset += length
        }
        let magic = source.read(offset, 8)
        if magic.starts(with: Array("fLaC".utf8)) {
            tags.fill(from: readFLAC(source, at: offset + 4, wantPicture: wantPicture))
        } else if magic.count >= 8, Array(magic[magic.startIndex + 4..<magic.startIndex + 8]) == Array("ftyp".utf8) {
            tags.fill(from: readMP4(source, wantPicture: wantPicture))
        } else if magic.starts(with: Array("RIFF".utf8)) {
            tags.fill(from: readWAV(source))
        } else if ["mp3", "mp2", "mpga"].contains(fileExtension.lowercased()) || (magic.first == 0xFF && magic.count > 1 && magic[magic.startIndex + 1] & 0xE0 == 0xE0) {
            tags.fill(from: readMPEGLength(source, at: offset))
            tags.fill(from: readID3v1(source))
        }
        return tags
    }

    // ------------------------------------------------------------- ID3v2 --

    /** One ID3v2 tag at [offset], and its whole length, or nil if there is none there. */
    private static func readID3v2(_ source: ByteSource, at offset: Int64, wantPicture: Bool) -> (AudioTags, Int64)? {
        let header = [UInt8](source.read(offset, 10))
        guard header.count == 10, header[0] == 0x49, header[1] == 0x44, header[2] == 0x33 else { return nil }
        let version = Int(header[3])
        guard (2...4).contains(version) else { return nil }
        let flags = header[5]
        let tagSize = syncsafe(header, 6)
        let total = Int64(10 + tagSize + (flags & 0x10 != 0 ? 10 : 0))
        var tags = AudioTags()

        // A tag unsynchronised as a whole (ID3v2.2/2.3) has to be read in full and undone first.
        var body: ByteSource = OffsetSource(base: source, start: offset + 10, length: Int64(tagSize))
        if flags & 0x80 != 0 && version < 4 {
            body = DataSource(data: unsynchronise(source.read(offset + 10, tagSize)))
        }
        var position: Int64 = 0
        if flags & 0x40 != 0 && version >= 3 {
            let ext = [UInt8](body.read(0, 4))
            guard ext.count == 4 else { return (tags, total) }
            position = version == 4 ? Int64(syncsafe(ext, 0)) : Int64(bigEndian(ext, 0, 4)) + 4
        }

        let idLength = version == 2 ? 3 : 4
        let headerLength = version == 2 ? 6 : 10
        var pictureType: UInt8?
        while position + Int64(headerLength) <= body.size {
            let frameHeader = [UInt8](body.read(position, headerLength))
            guard frameHeader.count == headerLength, frameHeader[0] != 0 else { break }
            let id = String(decoding: frameHeader[0..<idLength], as: UTF8.self)
            let size: Int
            switch version {
            case 2: size = bigEndian(frameHeader, 3, 3)
            case 3: size = bigEndian(frameHeader, 4, 4)
            default: size = syncsafe(frameHeader, 4)
            }
            let formatFlags = version == 4 ? frameHeader[9] : 0
            let start = position + Int64(headerLength)
            position = start + Int64(size)
            guard size > 0, position <= body.size else { if size <= 0 { continue } else { break } }
            let isPicture = id == "APIC" || id == "PIC"
            if isPicture && !wantPicture { continue }
            // Compressed or encrypted frames are not worth undoing for a tag reader.
            if version == 4 && formatFlags & 0x0C != 0 { continue }
            if version == 3 && frameHeader[9] & 0xC0 != 0 { continue }
            guard isPicture || id.hasPrefix("T") else { continue }
            var content = body.read(start, size)
            if version == 4 && formatFlags & 0x01 != 0 { content = content.dropFirst(4) }
            if version == 4 && formatFlags & 0x02 != 0 { content = unsynchronise(content) }
            let bytes = [UInt8](content)

            if isPicture {
                if let (type, data) = id3Picture(bytes, v22: id == "PIC"), pictureType != 3 {
                    if tags.picture == nil || type == 3 {
                        tags.picture = data
                        pictureType = type
                    }
                }
                continue
            }
            guard let text = id3Text(bytes) else { continue }
            switch id {
            case "TIT2", "TT2": tags.title = tags.title ?? text
            case "TPE1", "TP1": tags.artist = tags.artist ?? text
            case "TPE2", "TP2": tags.albumArtist = tags.albumArtist ?? text
            case "TALB", "TAL": tags.album = tags.album ?? text
            case "TRCK", "TRK": tags.track = tags.track ?? leadingNumber(text)
            case "TPOS", "TPA": tags.disc = tags.disc ?? leadingNumber(text)
            case "TYER", "TYE", "TDRC", "TDOR", "TORY": tags.year = tags.year ?? year(text)
            case "TCON", "TCO": tags.genre = tags.genre ?? genre(text)
            case "TLEN", "TLE": tags.durationMs = tags.durationMs ?? Int64(text).flatMap { $0 > 0 ? $0 : nil }
            default: break
            }
        }
        return (tags, total)
    }

    /** The text of an ID3 text frame: its first value, in its encoding. */
    private static func id3Text(_ bytes: [UInt8]) -> String? {
        guard let encoding = bytes.first else { return nil }
        let text = decode(Array(bytes.dropFirst()), encoding: encoding)
        // Several values are separated by nulls; the first is the one to show.
        return clean(text.components(separatedBy: "\u{0}").first)
    }

    private static func id3Picture(_ bytes: [UInt8], v22: Bool) -> (UInt8, Data)? {
        guard bytes.count > 4 else { return nil }
        let encoding = bytes[0]
        var i = 1
        if v22 {
            i += 3
        } else {
            while i < bytes.count && bytes[i] != 0 { i += 1 }
            i += 1
        }
        guard i < bytes.count else { return nil }
        let type = bytes[i]
        i += 1
        // The description ends with one null, or two in UTF-16.
        if encoding == 1 || encoding == 2 {
            while i + 1 < bytes.count && !(bytes[i] == 0 && bytes[i + 1] == 0) { i += 2 }
            i += 2
        } else {
            while i < bytes.count && bytes[i] != 0 { i += 1 }
            i += 1
        }
        guard i < bytes.count else { return nil }
        return (type, Data(bytes[i...]))
    }

    private static func decode(_ bytes: [UInt8], encoding: UInt8) -> String {
        switch encoding {
        case 1:
            if bytes.count >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF {
                return String(bytes: bytes.dropFirst(2), encoding: .utf16BigEndian) ?? ""
            }
            if bytes.count >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE {
                return String(bytes: bytes.dropFirst(2), encoding: .utf16LittleEndian) ?? ""
            }
            return String(bytes: bytes, encoding: .utf16LittleEndian) ?? ""
        case 2: return String(bytes: bytes, encoding: .utf16BigEndian) ?? ""
        case 3: return String(decoding: bytes, as: UTF8.self)
        default: return String(bytes: bytes, encoding: .isoLatin1) ?? ""
        }
    }

    private static func unsynchronise(_ data: Data) -> Data {
        var out = [UInt8]()
        out.reserveCapacity(data.count)
        var previous: UInt8 = 0
        for byte in data {
            if previous == 0xFF && byte == 0x00 {
                previous = 0
                continue
            }
            out.append(byte)
            previous = byte
        }
        return Data(out)
    }

    // ------------------------------------------------------------- ID3v1 --

    private static func readID3v1(_ source: ByteSource) -> AudioTags {
        guard source.size >= 128 else { return AudioTags() }
        let bytes = [UInt8](source.read(source.size - 128, 128))
        guard bytes.count == 128, bytes[0] == 0x54, bytes[1] == 0x41, bytes[2] == 0x47 else { return AudioTags() }
        func field(_ start: Int, _ length: Int) -> String? {
            let slice = bytes[start..<start + length].prefix { $0 != 0 }
            return clean(String(bytes: slice, encoding: .isoLatin1))
        }
        var tags = AudioTags(title: field(3, 30), artist: field(33, 30), album: field(63, 30), year: field(93, 4).flatMap(year))
        if bytes[125] == 0 && bytes[126] != 0 { tags.track = Int(bytes[126]) }
        if Int(bytes[127]) < genres.count { tags.genre = genres[Int(bytes[127])] }
        return tags
    }

    // -------------------------------------------------------------- MPEG --

    /** Sample rate and length of an MP3, from its first frame (and the Xing/Info or VBRI header in it, if any). */
    private static func readMPEGLength(_ source: ByteSource, at offset: Int64) -> AudioTags {
        // The first frame is usually right after the tag; allow a little padding.
        let window = [UInt8](source.read(offset, 64 * 1024))
        var i = 0
        while i + 4 <= window.count {
            if window[i] == 0xFF && window[i + 1] & 0xE0 == 0xE0, let frame = mpegFrame(window, at: i) {
                let frameStart = offset + Int64(i)
                let header = [UInt8](source.read(frameStart, 200))
                var frames: Int?
                let xing = frame.xingOffset
                if header.count >= xing + 12 {
                    let tag = String(decoding: header[xing..<xing + 4], as: UTF8.self)
                    if (tag == "Xing" || tag == "Info") && header[xing + 7] & 0x01 != 0 {
                        frames = bigEndian(header, xing + 8, 4)
                    }
                }
                if frames == nil, header.count >= 36 + 18, String(decoding: header[36..<40], as: UTF8.self) == "VBRI" {
                    frames = bigEndian(header, 36 + 14, 4)
                }
                var tags = AudioTags(sampleRate: frame.sampleRate)
                if let frames, frames > 0 {
                    tags.durationMs = Int64(frames) * Int64(frame.samplesPerFrame) * 1000 / Int64(frame.sampleRate)
                } else if frame.bitRate > 0 {
                    // Constant bit rate: the length follows from the size.
                    var audio = source.size - frameStart
                    if source.size >= 128, source.read(source.size - 128, 3) == Data("TAG".utf8) { audio -= 128 }
                    tags.durationMs = audio * 8 / Int64(frame.bitRate)
                }
                return tags
            }
            i += 1
        }
        return AudioTags()
    }

    private struct MPEGFrame {
        let sampleRate: Int
        let bitRate: Int
        let samplesPerFrame: Int
        let xingOffset: Int
    }

    private static func mpegFrame(_ b: [UInt8], at i: Int) -> MPEGFrame? {
        let versionBits = (b[i + 1] >> 3) & 0x03 // 3 = MPEG 1, 2 = MPEG 2, 0 = MPEG 2.5
        let layerBits = (b[i + 1] >> 1) & 0x03 // 1 = Layer III
        let bitrateIndex = Int(b[i + 2] >> 4)
        let rateIndex = Int((b[i + 2] >> 2) & 0x03)
        guard versionBits != 1, layerBits == 1, bitrateIndex != 0, bitrateIndex != 15, rateIndex != 3 else { return nil }
        let mpeg1 = versionBits == 3
        let rates = [44100, 48000, 32000]
        let sampleRate = rates[rateIndex] / (mpeg1 ? 1 : versionBits == 2 ? 2 : 4)
        let bitrates1 = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
        let bitrates2 = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160]
        let bitRate = (mpeg1 ? bitrates1 : bitrates2)[bitrateIndex] * 1000
        let mono = (b[i + 3] >> 6) == 3
        let side = mpeg1 ? (mono ? 17 : 32) : (mono ? 9 : 17)
        return MPEGFrame(sampleRate: sampleRate, bitRate: bitRate, samplesPerFrame: mpeg1 ? 1152 : 576, xingOffset: 4 + side)
    }

    // -------------------------------------------------------------- FLAC --

    private static func readFLAC(_ source: ByteSource, at start: Int64, wantPicture: Bool) -> AudioTags {
        var tags = AudioTags()
        var offset = start
        var pictureType: UInt32?
        for _ in 0..<64 {
            let header = [UInt8](source.read(offset, 4))
            guard header.count == 4 else { break }
            let last = header[0] & 0x80 != 0
            let type = header[0] & 0x7F
            let length = bigEndian(header, 1, 3)
            let body = offset + 4
            switch type {
            case 0:
                let info = [UInt8](source.read(body, 18))
                if info.count == 18 {
                    let rate = (Int(info[10]) << 12) | (Int(info[11]) << 4) | (Int(info[12]) >> 4)
                    let samples = (Int64(info[13] & 0x0F) << 32) | Int64(bigEndian(info, 14, 4))
                    if rate > 0 {
                        tags.sampleRate = rate
                        if samples > 0 { tags.durationMs = samples * 1000 / Int64(rate) }
                    }
                }
            case 4:
                tags.fill(from: vorbisComments([UInt8](source.read(body, length))))
            case 6 where wantPicture:
                let bytes = [UInt8](source.read(body, length))
                if let (kind, data) = flacPicture(bytes), pictureType != 3, tags.picture == nil || kind == 3 {
                    tags.picture = data
                    pictureType = kind
                }
            default: break
            }
            offset = body + Int64(length)
            if last { break }
        }
        return tags
    }

    private static func vorbisComments(_ b: [UInt8]) -> AudioTags {
        var tags = AudioTags()
        guard b.count >= 8 else { return tags }
        var i = 4 + littleEndian(b, 0, 4)
        guard i + 4 <= b.count else { return tags }
        let count = littleEndian(b, i, 4)
        i += 4
        for _ in 0..<min(count, 1000) {
            guard i + 4 <= b.count else { break }
            let length = littleEndian(b, i, 4)
            i += 4
            guard length >= 0, i + length <= b.count else { break }
            let comment = String(decoding: b[i..<i + length], as: UTF8.self)
            i += length
            guard let equals = comment.firstIndex(of: "=") else { continue }
            let key = comment[..<equals].uppercased()
            guard let value = clean(String(comment[comment.index(after: equals)...])) else { continue }
            switch key {
            case "TITLE": tags.title = tags.title ?? value
            case "ARTIST": tags.artist = tags.artist ?? value
            case "ALBUMARTIST", "ALBUM ARTIST", "ALBUM_ARTIST": tags.albumArtist = tags.albumArtist ?? value
            case "ALBUM": tags.album = tags.album ?? value
            case "TRACKNUMBER": tags.track = tags.track ?? leadingNumber(value)
            case "DISCNUMBER": tags.disc = tags.disc ?? leadingNumber(value)
            case "DATE", "YEAR", "ORIGINALDATE": tags.year = tags.year ?? year(value)
            case "GENRE": tags.genre = tags.genre ?? genre(value)
            default: break
            }
        }
        return tags
    }

    private static func flacPicture(_ b: [UInt8]) -> (UInt32, Data)? {
        guard b.count >= 32 else { return nil }
        let type = UInt32(bigEndian(b, 0, 4))
        var i = 4
        let mimeLength = bigEndian(b, i, 4)
        i += 4 + mimeLength
        guard i + 4 <= b.count else { return nil }
        let descriptionLength = bigEndian(b, i, 4)
        i += 4 + descriptionLength + 16
        guard i + 4 <= b.count else { return nil }
        let length = bigEndian(b, i, 4)
        i += 4
        guard length > 0, i + length <= b.count else { return nil }
        return (type, Data(b[i..<i + length]))
    }

    // --------------------------------------------------------------- MP4 --

    private static func readMP4(_ source: ByteSource, wantPicture: Bool) -> AudioTags {
        var tags = AudioTags()
        for (type, start, length) in atoms(source, from: 0, to: source.size) where type == "moov" {
            for (child, childStart, childLength) in atoms(source, from: start, to: start + length) {
                if child == "mvhd" {
                    let b = [UInt8](source.read(childStart, 32))
                    guard b.count >= 24 else { continue }
                    let version = b[0]
                    let timescale = version == 1 ? bigEndian(b, 20, 4) : bigEndian(b, 12, 4)
                    let duration = version == 1 && b.count >= 32
                        ? (Int64(bigEndian(b, 24, 4)) << 32) | Int64(bigEndian(b, 28, 4))
                        : Int64(bigEndian(b, 16, 4))
                    if timescale > 0 && duration > 0 { tags.durationMs = duration * 1000 / Int64(timescale) }
                } else if child == "udta" {
                    for (meta, metaStart, metaLength) in atoms(source, from: childStart, to: childStart + childLength) where meta == "meta" {
                        // "meta" is a full atom: a version and flags before its children.
                        for (list, listStart, listLength) in atoms(source, from: metaStart + 4, to: metaStart + metaLength) where list == "ilst" {
                            tags.fill(from: itemList(source, from: listStart, to: listStart + listLength, wantPicture: wantPicture))
                        }
                    }
                }
            }
        }
        return tags
    }

    private static func itemList(_ source: ByteSource, from start: Int64, to end: Int64, wantPicture: Bool) -> AudioTags {
        var tags = AudioTags()
        for (item, itemStart, itemLength) in atoms(source, from: start, to: end) {
            if item == "covr" && !wantPicture { continue }
            guard itemLength < 16 * 1024 * 1024 else { continue }
            for (data, dataStart, dataLength) in atoms(source, from: itemStart, to: itemStart + itemLength) where data == "data" && dataLength >= 8 {
                let b = [UInt8](source.read(dataStart, Int(dataLength)))
                guard b.count == Int(dataLength) else { continue }
                let value = Array(b[8...])
                let text = { clean(String(decoding: value, as: UTF8.self)) }
                switch item {
                case "\u{A9}nam": tags.title = tags.title ?? text()
                case "\u{A9}ART": tags.artist = tags.artist ?? text()
                case "aART": tags.albumArtist = tags.albumArtist ?? text()
                case "\u{A9}alb": tags.album = tags.album ?? text()
                case "\u{A9}day": tags.year = tags.year ?? text().flatMap(year)
                case "\u{A9}gen": tags.genre = tags.genre ?? text().flatMap(genre)
                case "gnre" where value.count >= 2:
                    let index = bigEndian(value, 0, 2) - 1
                    if tags.genre == nil, index >= 0, index < genres.count { tags.genre = genres[index] }
                case "trkn" where value.count >= 4:
                    let number = bigEndian(value, 2, 2)
                    if number > 0 { tags.track = tags.track ?? number }
                case "disk" where value.count >= 4:
                    let number = bigEndian(value, 2, 2)
                    if number > 0 { tags.disc = tags.disc ?? number }
                case "covr":
                    if tags.picture == nil, !value.isEmpty { tags.picture = Data(value) }
                default: break
                }
                break
            }
        }
        return tags
    }

    /** The atoms between [start] and [end]: their type, where their content starts, and its length. */
    private static func atoms(_ source: ByteSource, from start: Int64, to end: Int64) -> [(String, Int64, Int64)] {
        var result: [(String, Int64, Int64)] = []
        var offset = start
        while offset + 8 <= end, result.count < 512 {
            let header = [UInt8](source.read(offset, 16))
            guard header.count >= 8 else { break }
            var size = Int64(bigEndian(header, 0, 4))
            var headerLength: Int64 = 8
            if size == 1 && header.count == 16 {
                size = (Int64(bigEndian(header, 8, 4)) << 32) | Int64(bigEndian(header, 12, 4))
                headerLength = 16
            } else if size == 0 {
                size = end - offset
            }
            guard size >= headerLength, offset + size <= end else { break }
            let type = String(decoding: header[4..<8], as: UTF8.self)
            let latin = String(bytes: header[4..<8], encoding: .isoLatin1) ?? type
            result.append((latin, offset + headerLength, size - headerLength))
            offset += size
        }
        return result
    }

    // --------------------------------------------------------------- WAV --

    private static func readWAV(_ source: ByteSource) -> AudioTags {
        var tags = AudioTags()
        var byteRate = 0
        var offset: Int64 = 12
        for _ in 0..<64 {
            let header = [UInt8](source.read(offset, 8))
            guard header.count == 8 else { break }
            let id = String(decoding: header[0..<4], as: UTF8.self)
            let length = Int64(littleEndian(header, 4, 4))
            if id == "fmt " {
                let fmt = [UInt8](source.read(offset + 8, 16))
                if fmt.count == 16 {
                    tags.sampleRate = littleEndian(fmt, 4, 4)
                    byteRate = littleEndian(fmt, 8, 4)
                }
            } else if id == "data", byteRate > 0 {
                tags.durationMs = min(length, source.size - offset - 8) * 1000 / Int64(byteRate)
            } else if id == "id3 " || id == "ID3 " {
                if let (id3, _) = readID3v2(OffsetSource(base: source, start: offset + 8, length: length), at: 0, wantPicture: false) {
                    tags.fill(from: id3)
                }
            }
            offset += 8 + length + (length & 1)
        }
        return tags
    }

    // ----------------------------------------------------------- helpers --

    private static func syncsafe(_ b: [UInt8], _ i: Int) -> Int {
        (Int(b[i] & 0x7F) << 21) | (Int(b[i + 1] & 0x7F) << 14) | (Int(b[i + 2] & 0x7F) << 7) | Int(b[i + 3] & 0x7F)
    }

    private static func bigEndian(_ b: [UInt8], _ i: Int, _ count: Int) -> Int {
        var value = 0
        for k in 0..<count where i + k < b.count { value = (value << 8) | Int(b[i + k]) }
        return value
    }

    private static func littleEndian(_ b: [UInt8], _ i: Int, _ count: Int) -> Int {
        var value = 0
        for k in (0..<count).reversed() where i + k < b.count { value = (value << 8) | Int(b[i + k]) }
        return value
    }

    private static func clean(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{0}"))),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /** "3/12" → 3. */
    static func leadingNumber(_ text: String) -> Int? {
        let digits = text.trimmingCharacters(in: .whitespaces).prefix { $0.isNumber }
        guard let number = Int(digits), number > 0 else { return nil }
        return number
    }

    /** "1999", "2004-05-01" → the year. */
    static func year(_ text: String) -> Int? {
        let digits = text.trimmingCharacters(in: .whitespaces).prefix(4)
        guard digits.count == 4, let value = Int(digits), value > 1000 else { return nil }
        return value
    }

    /** "(17)", "(17)Rock", "17" and "Rock" from ID3 → the genre's name. */
    static func genre(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("("), let close = text.firstIndex(of: ")") {
            let number = Int(text[text.index(after: text.startIndex)..<close])
            let rest = text[text.index(after: close)...].trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { return rest }
            if let number, number >= 0, number < genres.count { return genres[number] }
            return nil
        }
        if let number = Int(text) {
            return number >= 0 && number < genres.count ? genres[number] : nil
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\u{0}"))
        return text.isEmpty ? nil : text
    }

    /** The ID3v1 genres, by number. */
    static let genres = [
        "Blues", "Classic Rock", "Country", "Dance", "Disco", "Funk", "Grunge", "Hip-Hop", "Jazz", "Metal",
        "New Age", "Oldies", "Other", "Pop", "R&B", "Rap", "Reggae", "Rock", "Techno", "Industrial",
        "Alternative", "Ska", "Death Metal", "Pranks", "Soundtrack", "Euro-Techno", "Ambient", "Trip-Hop", "Vocal", "Jazz+Funk",
        "Fusion", "Trance", "Classical", "Instrumental", "Acid", "House", "Game", "Sound Clip", "Gospel", "Noise",
        "Alternative Rock", "Bass", "Soul", "Punk", "Space", "Meditative", "Instrumental Pop", "Instrumental Rock", "Ethnic", "Gothic",
        "Darkwave", "Techno-Industrial", "Electronic", "Pop-Folk", "Eurodance", "Dream", "Southern Rock", "Comedy", "Cult", "Gangsta",
        "Top 40", "Christian Rap", "Pop/Funk", "Jungle", "Native American", "Cabaret", "New Wave", "Psychedelic", "Rave", "Showtunes",
        "Trailer", "Lo-Fi", "Tribal", "Acid Punk", "Acid Jazz", "Polka", "Retro", "Musical", "Rock & Roll", "Hard Rock",
    ]
}

/** A window of another source, as if it were a file of its own. */
private struct OffsetSource: ByteSource {
    let base: ByteSource
    let start: Int64
    let length: Int64
    var size: Int64 { max(0, min(length, base.size - start)) }

    func read(_ offset: Int64, _ count: Int) -> Data {
        guard offset >= 0, offset < size else { return Data() }
        return base.read(start + offset, Int(min(Int64(count), size - offset)))
    }
}
