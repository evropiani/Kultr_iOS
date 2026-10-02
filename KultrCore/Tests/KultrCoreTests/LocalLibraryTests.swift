import XCTest
@testable import KultrCore

final class LocalCatalogTests: XCTestCase {
    private func track(
        _ name: String,
        _ folder: String,
        album: String? = nil,
        artist: String? = nil,
        albumArtist: String? = nil,
        number: Int? = nil,
        disc: Int? = nil,
        genre: String? = nil
    ) -> LocalTrack {
        LocalTrack(
            path: "folder|\(folder)/\(name)",
            fileName: name,
            folderKey: folder,
            folderName: (folder as NSString).lastPathComponent,
            modified: 1_700_000_000_000,
            size: 1_000,
            artist: artist,
            albumArtist: albumArtist,
            album: album,
            track: number,
            disc: disc,
            genre: genre,
            durationMs: 200_400
        )
    }

    func testUntaggedFilesTakeTheirNamesFromTheFileAndFolder() {
        let catalog = LocalCatalogBuilder.build([track("01 Intro.mp3", "Music/Demo Tape")])
        let song = catalog.songs[0]
        XCTAssertEqual(song.title, "01 Intro")
        XCTAssertEqual(song.album, "Demo Tape")
        XCTAssertEqual(catalog.albums[0].artist, LocalCatalogBuilder.unknownArtist)
        XCTAssertEqual(song.duration, 200)
        XCTAssertEqual(song.suffix, "mp3")
        XCTAssertTrue(song.id.hasPrefix(LocalCatalogBuilder.songPrefix))
        XCTAssertEqual(song.id, LocalCatalogBuilder.songId(song.path ?? ""))
        XCTAssertEqual(song.created, "2023-11-14T22:13:20Z")
    }

    func testAlbumsWithTheSameNameStayApartUnlessTheirArtistSaysOtherwise() {
        let catalog = LocalCatalogBuilder.build([
            // Two different "Greatest Hits", no album artist, in two folders: two albums.
            track("a.mp3", "Music/A", album: "Greatest Hits", artist: "A"),
            track("b.mp3", "Music/B", album: "Greatest Hits", artist: "B"),
            // A two-disc album in two folders, tagged with its album artist: one album.
            track("1.flac", "Music/Big/CD1", album: "Big", artist: "C", albumArtist: "C", number: 1, disc: 1),
            track("2.flac", "Music/Big/CD2", album: "Big", artist: "C", albumArtist: "C", number: 1, disc: 2),
        ])
        XCTAssertEqual(catalog.albums.count, 3)
        let big = catalog.albums.first { $0.name == "Big" }
        XCTAssertEqual(big?.songCount, 2)
        XCTAssertEqual(catalog.songs.filter { $0.albumId == big?.id }.map { $0.discNumber }, [1, 2])
        XCTAssertEqual(Set(catalog.artists.map { $0.name }), ["A", "B", "C"])
    }

    func testCompilationsWithoutAnAlbumArtistAreByVariousArtists() {
        let catalog = LocalCatalogBuilder.build([
            track("1.mp3", "Music/Mix", album: "Mix", artist: "X", genre: "House"),
            track("2.mp3", "Music/Mix", album: "Mix", artist: "Y", genre: "House"),
        ])
        let album = catalog.albums[0]
        XCTAssertEqual(album.artist, LocalCatalogBuilder.variousArtists)
        XCTAssertEqual(album.isCompilation, true)
        // Each track keeps its own artist name.
        XCTAssertEqual(catalog.songs.map { $0.artist }, ["X", "Y"])
        XCTAssertEqual(album.genre, "House")
        XCTAssertEqual(catalog.genres.count, 1)
        XCTAssertEqual(catalog.genres[0].songCount, 2)
    }

    func testAFolderImageIsTheCoverAndYourOwnDataCarriesOver() {
        let t = track("1.mp3", "Music/Album", album: "Album", artist: "Z")
        let id = LocalCatalogBuilder.songId(t.path)
        var before = Song(id: id)
        before.playCount = 7
        before.played = "2026-09-01T10:00:00Z"
        before.starred = "2026-08-01T00:00:00Z"
        before.userRating = 4
        let catalog = LocalCatalogBuilder.build([t], covers: ["Music/Album": "local-art:abc"]) { $0 == id ? before : nil }
        let song = catalog.songs[0]
        XCTAssertEqual(song.coverArt, "local-art:abc")
        XCTAssertEqual(catalog.albums[0].coverArt, "local-art:abc")
        XCTAssertEqual(song.playCount, 7)
        XCTAssertEqual(song.userRating, 4)
        XCTAssertEqual(song.starred, "2026-08-01T00:00:00Z")
        XCTAssertEqual(catalog.albums[0].playCount, 7)
    }

    func testTracksAreInDiscAndTrackOrder() {
        let catalog = LocalCatalogBuilder.build([
            track("b.mp3", "Music/X", album: "X", artist: "X", number: 2),
            track("c.mp3", "Music/X", album: "X", artist: "X"),
            track("a.mp3", "Music/X", album: "X", artist: "X", number: 1),
        ])
        XCTAssertEqual(catalog.songs.map { $0.track }, [1, 2, nil])
        XCTAssertNil(catalog.albums[0].coverArt)
    }
}

final class AudioTagTests: XCTestCase {
    private func u32(_ v: Int) -> [UInt8] { [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }
    private func le32(_ v: Int) -> [UInt8] { u32(v).reversed() }
    private func syncsafe(_ v: Int) -> [UInt8] { [UInt8((v >> 21) & 0x7F), UInt8((v >> 14) & 0x7F), UInt8((v >> 7) & 0x7F), UInt8(v & 0x7F)] }

    private func id3Frame(_ id: String, _ body: [UInt8], v4: Bool) -> [UInt8] {
        Array(id.utf8) + (v4 ? syncsafe(body.count) : u32(body.count)) + [0, 0] + body
    }

    private func latin(_ text: String) -> [UInt8] { [0] + Array(text.utf8) }

    private func id3(_ frames: [[UInt8]], v4: Bool) -> [UInt8] {
        let body = frames.flatMap { $0 }
        return Array("ID3".utf8) + [v4 ? 4 : 3, 0, 0] + syncsafe(body.count) + body
    }

    /** An MPEG-1 Layer III frame at 44.1 kHz, stereo, with a Xing header counting [frames]. */
    private func mp3Frame(frames: Int) -> [UInt8] {
        var frame = [UInt8](repeating: 0, count: 417)
        frame[0] = 0xFF
        frame[1] = 0xFB
        frame[2] = 0x90 // 128 kbps, 44.1 kHz
        frame[3] = 0x00
        let xing = 4 + 32
        frame.replaceSubrange(xing..<xing + 4, with: Array("Xing".utf8))
        frame.replaceSubrange(xing + 4..<xing + 8, with: u32(0x01))
        frame.replaceSubrange(xing + 8..<xing + 12, with: u32(frames))
        return frame
    }

    func testReadsID3v23TagsAndTheLengthFromXing() {
        let picture: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]
        let apic = [0] + Array("image/jpeg".utf8) + [0, 3] + Array("front".utf8) + [0] + picture
        let tag = id3([
            id3Frame("TIT2", latin("Daniel"), v4: false),
            id3Frame("TPE1", latin("Natasha Beller"), v4: false),
            id3Frame("TPE2", latin("Natasha Beller"), v4: false),
            id3Frame("TALB", latin("Fairytale"), v4: false),
            id3Frame("TRCK", latin("3/12"), v4: false),
            id3Frame("TPOS", latin("1/2"), v4: false),
            id3Frame("TYER", latin("2018"), v4: false),
            id3Frame("TCON", latin("(27)"), v4: false),
            id3Frame("APIC", apic, v4: false),
        ], v4: false)
        let file = Data(tag + mp3Frame(frames: 1000))
        let tags = AudioTagReader.read(DataSource(data: file), fileExtension: "mp3", picture: true)
        XCTAssertEqual(tags.title, "Daniel")
        XCTAssertEqual(tags.artist, "Natasha Beller")
        XCTAssertEqual(tags.albumArtist, "Natasha Beller")
        XCTAssertEqual(tags.album, "Fairytale")
        XCTAssertEqual(tags.track, 3)
        XCTAssertEqual(tags.disc, 1)
        XCTAssertEqual(tags.year, 2018)
        XCTAssertEqual(tags.genre, "Trip-Hop")
        XCTAssertEqual(tags.sampleRate, 44100)
        XCTAssertEqual(tags.durationMs, 1000 * 1152 * 1000 / 44100)
        XCTAssertEqual(tags.picture, Data(picture))

        // Without asking for the picture, it is not read.
        XCTAssertNil(AudioTagReader.read(DataSource(data: file), fileExtension: "mp3").picture)
    }

    func testReadsID3v24WithUTF8AndUTF16Text() {
        let utf16: [UInt8] = [1, 0xFF, 0xFE] + Array("Café".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
        let tag = id3([
            id3Frame("TIT2", [3] + Array("Ünïcode ♫".utf8), v4: true),
            id3Frame("TPE1", utf16, v4: true),
            id3Frame("TDRC", [3] + Array("2004-05-01".utf8), v4: true),
            id3Frame("TCON", [3] + Array("Drum & Bass".utf8), v4: true),
        ], v4: true)
        let tags = AudioTagReader.read(DataSource(data: Data(tag + mp3Frame(frames: 10))), fileExtension: "mp3")
        XCTAssertEqual(tags.title, "Ünïcode ♫")
        XCTAssertEqual(tags.artist, "Café")
        XCTAssertEqual(tags.year, 2004)
        XCTAssertEqual(tags.genre, "Drum & Bass")
    }

    func testReadsFLACCommentsLengthAndPicture() {
        var info = [UInt8](repeating: 0, count: 34)
        // 44100 Hz, 441000 samples: ten seconds.
        let rate = 44100
        info[10] = UInt8((rate >> 12) & 0xFF)
        info[11] = UInt8((rate >> 4) & 0xFF)
        info[12] = UInt8((rate & 0x0F) << 4) | 0x02
        info.replaceSubrange(14..<18, with: u32(441_000))
        let comments = ["TITLE=Lonely", "ARTIST=Back On Earth", "ALBUMARTIST=Back On Earth", "ALBUM=Love", "TRACKNUMBER=4", "DISCNUMBER=1/1", "DATE=2010", "GENRE=Ambient"]
        let vendor = Array("kultr".utf8)
        var vorbis = le32(vendor.count) + vendor + le32(comments.count)
        for comment in comments { vorbis += le32(comment.utf8.count) + Array(comment.utf8) }
        let picture: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        let mime = Array("image/png".utf8)
        let pictureBlock = u32(3) + u32(mime.count) + mime + u32(0) + u32(500) + u32(500) + u32(24) + u32(0) + u32(picture.count) + picture
        func block(_ type: UInt8, _ body: [UInt8], last: Bool = false) -> [UInt8] {
            [type | (last ? 0x80 : 0), UInt8((body.count >> 16) & 0xFF), UInt8((body.count >> 8) & 0xFF), UInt8(body.count & 0xFF)] + body
        }
        let file = Array("fLaC".utf8) + block(0, info) + block(4, vorbis) + block(6, pictureBlock, last: true) + [0xFF, 0xF8]
        let tags = AudioTagReader.read(DataSource(data: Data(file)), fileExtension: "flac", picture: true)
        XCTAssertEqual(tags.title, "Lonely")
        XCTAssertEqual(tags.artist, "Back On Earth")
        XCTAssertEqual(tags.albumArtist, "Back On Earth")
        XCTAssertEqual(tags.album, "Love")
        XCTAssertEqual(tags.track, 4)
        XCTAssertEqual(tags.disc, 1)
        XCTAssertEqual(tags.year, 2010)
        XCTAssertEqual(tags.genre, "Ambient")
        XCTAssertEqual(tags.sampleRate, 44100)
        XCTAssertEqual(tags.durationMs, 10_000)
        XCTAssertEqual(tags.picture, Data(picture))
    }

    func testReadsMP4ItemsAndLength() {
        func atom(_ type: [UInt8], _ body: [UInt8]) -> [UInt8] { u32(8 + body.count) + type + body }
        func atom(_ type: String, _ body: [UInt8]) -> [UInt8] { atom(Array(type.utf8), body) }
        func data(_ kind: Int, _ value: [UInt8]) -> [UInt8] { atom("data", u32(kind) + u32(0) + value) }
        let copyright: UInt8 = 0xA9
        let ilst = atom("ilst",
            atom([copyright] + Array("nam".utf8), data(1, Array("Feijão".utf8)))
            + atom([copyright] + Array("ART".utf8), data(1, Array("Dr. Quandary".utf8)))
            + atom("aART", data(1, Array("Various".utf8)))
            + atom([copyright] + Array("alb".utf8), data(1, Array("netBloc Vol. 42".utf8)))
            + atom("trkn", data(0, [0, 0, 0, 1, 0, 11, 0, 0]))
            + atom("disk", data(0, [0, 0, 0, 2, 0, 2]))
            + atom([copyright] + Array("day".utf8), data(1, Array("2013-01-01T00:00:00Z".utf8)))
            + atom("gnre", data(0, [0, 9]))
            + atom("covr", data(13, [0xFF, 0xD8, 9]))
        )
        let meta = atom("meta", u32(0) + atom("hdlr", [UInt8](repeating: 0, count: 25)) + ilst)
        var mvhd = u32(0) + u32(0) + u32(0) + u32(1000) + u32(218_000)
        mvhd += [UInt8](repeating: 0, count: 80)
        let moov = atom("moov", atom("mvhd", mvhd) + atom("udta", meta))
        let file = atom("ftyp", Array("M4A ".utf8) + u32(0)) + atom("mdat", [1, 2, 3]) + moov
        let tags = AudioTagReader.read(DataSource(data: Data(file)), fileExtension: "m4a", picture: true)
        XCTAssertEqual(tags.title, "Feijão")
        XCTAssertEqual(tags.artist, "Dr. Quandary")
        XCTAssertEqual(tags.albumArtist, "Various")
        XCTAssertEqual(tags.album, "netBloc Vol. 42")
        XCTAssertEqual(tags.track, 1)
        XCTAssertEqual(tags.disc, 2)
        XCTAssertEqual(tags.year, 2013)
        XCTAssertEqual(tags.genre, "Jazz")
        XCTAssertEqual(tags.durationMs, 218_000)
        XCTAssertEqual(tags.picture, Data([0xFF, 0xD8, 9]))
    }

    func testFilesWithoutTagsGiveNothingButDoNotFail() {
        XCTAssertEqual(AudioTagReader.read(DataSource(data: Data()), fileExtension: "mp3"), AudioTags())
        XCTAssertNil(AudioTagReader.read(DataSource(data: Data([1, 2, 3, 4, 5, 6, 7, 8, 9])), fileExtension: "flac").title)
    }

    func testGenresAndNumbersAreCleanedUp() {
        XCTAssertEqual(AudioTagReader.genre("(17)"), "Rock")
        XCTAssertEqual(AudioTagReader.genre("(17)Rock 'n' Roll"), "Rock 'n' Roll")
        XCTAssertEqual(AudioTagReader.genre("13"), "Pop")
        XCTAssertEqual(AudioTagReader.genre("Shoegaze"), "Shoegaze")
        XCTAssertEqual(AudioTagReader.leadingNumber("07/12"), 7)
        XCTAssertNil(AudioTagReader.leadingNumber("0"))
        XCTAssertEqual(AudioTagReader.year("1999-12-31"), 1999)
    }
}

final class UpdateTests: XCTestCase {
    func testVersionsCompareNumberByNumber() {
        XCTAssertTrue(Versions.isNewer("v1.5.0", than: "1.4.0"))
        XCTAssertTrue(Versions.isNewer("1.10.0", than: "1.9.2"))
        XCTAssertTrue(Versions.isNewer("2.0", than: "1.99.99"))
        XCTAssertFalse(Versions.isNewer("1.4.0", than: "1.4.0"))
        XCTAssertFalse(Versions.isNewer("v1.4", than: "1.4.0"))
        XCTAssertFalse(Versions.isNewer("1.3.9", than: "1.4.0"))
        XCTAssertTrue(Versions.isNewer("1.5.0", than: "1.5.0-beta"))
        XCTAssertFalse(Versions.isNewer("1.5.0-beta", than: "1.5.0"))
        XCTAssertFalse(Versions.isNewer("nightly", than: "1.4.0"))
        XCTAssertEqual(Versions.fromTag("v1.4.0"), "1.4.0")
    }

    func testReleaseNotesReadHeadingsPointsAndParagraphs() {
        let notes = """
        ## What's new

        - **Search in the bar.** Tap the search
          button and it grows.
          - A smaller point
        - Plain point

        A paragraph
        over two lines.
        """
        XCTAssertEqual(ReleaseNotes.parse(notes), [
            .heading(level: 2, text: [.init("What's new")]),
            .bullet(level: 0, text: [.init("Search in the bar.", bold: true), .init(" Tap the search button and it grows.")]),
            .bullet(level: 1, text: [.init("A smaller point")]),
            .bullet(level: 0, text: [.init("Plain point")]),
            .paragraph([.init("A paragraph over two lines.")]),
        ])
    }

    func testReleaseNotesLeaveOutTheInstallSection() {
        let notes = """
        ## What's new
        - One
        ## Install
        Download **Kultr.ipa** below.
        ### Checksums
        abc
        ## Thanks
        Everyone.
        """
        XCTAssertEqual(ReleaseNotes.parse(notes), [
            .heading(level: 2, text: [.init("What's new")]),
            .bullet(level: 0, text: [.init("One")]),
            .heading(level: 2, text: [.init("Thanks")]),
            .paragraph([.init("Everyone.")]),
        ])
    }

    func testReleaseNotesReadCodeLinksAndEscapes() {
        XCTAssertEqual(
            ReleaseNotes.inline("Key `3C:26`, see [the page](https://kultr.cc/) \\*really\\*"),
            [.init("Key "), .init("3C:26", code: true), .init(", see "), .init("the page", link: "https://kultr.cc/"), .init(" *really*")]
        )
        // Unclosed marks are kept as written.
        XCTAssertEqual(ReleaseNotes.inline("a ` b [c"), [.init("a ` b [c")])
    }
}
