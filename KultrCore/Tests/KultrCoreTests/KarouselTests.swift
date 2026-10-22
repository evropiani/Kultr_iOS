import XCTest
@testable import KultrCore

/** The same numbers every run, so a failing test fails the same way twice. */
private struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private struct Offline: Error {}

/** A server with Last.fm: similar songs, similar artists and their best-known songs. */
@MainActor
private final class Server: KarouselSources {
    let offline: Bool
    let library: [Song]
    let stationSongs: [Song]

    init(offline: Bool = false, library: [Song] = []) {
        self.offline = offline
        self.library = library
        let artists = ["Phoenix", "Air", "Justice", "Daft Punk"]
        stationSongs = (1...12).map { i in Song(id: "st-\(i)", title: "Station song \(i)", artist: artists[i % 4]) }
            + [Song(id: "st-omt", title: "One More Time (Remastered 2021)", artist: "Daft Punk")]
    }

    private func online() throws {
        if offline { throw Offline() }
    }

    func station(_ seed: Song) async throws -> [Song] {
        try online()
        return stationSongs
    }

    func similarArtists(_ artist: ArtistRef) async throws -> [ArtistRef] {
        try online()
        return artist.name == "Daft Punk" ? ["Justice", "Cassius", "Air"].map { ArtistRef(name: $0, id: "ar-\($0)") } : []
    }

    func topSongs(_ artist: ArtistRef, count: Int) async throws -> [Song] {
        try online()
        return Array((1...6).map { Song(id: "top-\(artist.name)-\($0)", title: "\(artist.name) hit \($0)", artist: artist.name) }.prefix(count))
    }

    func byArtists(_ artists: [ArtistRef]) async throws -> [Song] {
        let names = Set(artists.map { Karousel.artistKey($0.name) })
        return library.filter { names.contains(Karousel.artistKey($0.artist)) }
    }

    func inGenres(_ genres: Set<String>, count: Int) async throws -> [Song] {
        Array(library.filter { $0.genre.map(genres.contains) ?? false }.prefix(count))
    }

    func favourites(_ count: Int) async throws -> [Song] { Array(library.prefix(count)) }
}

@MainActor
final class KarouselTests: XCTestCase {
    private func song(_ artist: String, _ title: String, genre: String? = nil) -> Song {
        Song(id: "\(artist)-\(title)", title: title, artist: artist, artistId: "ar-\(artist)", genre: genre)
    }

    private var playing: Song { song("Daft Punk", "One More Time") }

    func testKeepsTheMusicGoingWithMusicLikeWhatIsPlaying() async {
        let next = await Karousel(sources: Server()).next(
            Karousel.Input(
                seeds: [playing],
                exclude: ["st-1", playing.id, Karousel.key(playing)],
                count: 10,
                random: SeededRandom(7)
            )
        )
        XCTAssertEqual(next.count, 10)
        XCTAssertEqual(Set(next.map { $0.id }).count, next.count, "no song twice")
        // What is queued, and the same song remastered on the station, aren't picked again.
        XCTAssertFalse(next.contains { $0.id == "st-1" })
        XCTAssertFalse(next.contains { $0.title.hasPrefix("One More Time") })
        // Mostly the station, with songs by similar artists and by the artist playing.
        XCTAssertGreaterThanOrEqual(next.filter { $0.id.hasPrefix("st-") }.count, 4)
        XCTAssertTrue(next.contains { $0.id.hasPrefix("top-") && $0.artist != "Daft Punk" })
        XCTAssertTrue(next.contains { $0.id.hasPrefix("top-Daft Punk") })
        // At most two songs by one artist, and never the same artist twice in a row.
        XCTAssertTrue(Dictionary(grouping: next) { $0.artist ?? "" }.values.allSatisfy { $0.count <= Karousel.maxPerArtist })
        XCTAssertFalse(zip(next, next.dropFirst()).contains { $0.artist == $1.artist })
    }

    func testWithNoConnectionItCarriesOnWithTheLibrary() async {
        let library = [
            song("Daft Punk", "Aerodynamic"),
            song("Massive Attack", "Teardrop", genre: "Trip Hop"),
            song("Portishead", "Roads", genre: "Trip Hop"),
            song("Air", "Sexy Boy"),
            song("Massive Attack", "Angel", genre: "Trip Hop"),
            song("Massive Attack", "Unfinished Sympathy", genre: "Trip Hop"),
        ]
        let seed = song("Massive Attack", "Angel", genre: "Trip Hop")
        let next = await Karousel(sources: Server(offline: true, library: library)).next(
            Karousel.Input(seeds: [seed], exclude: [seed.id], count: 4, random: SeededRandom(1))
        )
        XCTAssertEqual(next.count, 4)
        // The same artist first (no more than two), then the same genre, then what the user plays.
        XCTAssertEqual(Set(next.filter { $0.artist == "Massive Attack" }.map { $0.title }), ["Teardrop", "Unfinished Sympathy"])
        XCTAssertTrue(next.contains { $0.title == "Roads" })
        XCTAssertFalse(next.contains { $0.title == "Angel" })
    }

    func testNothingToGoOnMeansNothingAdded() async {
        let karousel = Karousel(sources: Server(offline: true))
        let none1 = await karousel.next(Karousel.Input(seeds: [playing]))
        XCTAssertTrue(none1.isEmpty)
        let none2 = await karousel.next(Karousel.Input(seeds: []))
        XCTAssertTrue(none2.isEmpty)
        // Internet radio has nothing to be like.
        let radio = await karousel.next(Karousel.Input(seeds: [Song(id: "r", title: "FM", kultrStreamUrl: "https://radio")]))
        XCTAssertTrue(radio.isEmpty)
    }

    func testSongsAreKnownByTheirFirstArtistAndTitle() {
        XCTAssertEqual(Karousel.artistKey("Daft Punk feat. Pharrell Williams"), "daft punk")
        XCTAssertEqual(Karousel.artistKey("Beyoncé, JAY-Z"), "beyonce")
        XCTAssertEqual(Karousel.key(song("Daft Punk", "Get Lucky")), Karousel.key(song("Daft Punk ft. Pharrell", "Get Lucky (Radio Edit)")))
        XCTAssertEqual(Karousel.key(song("Queen", "Bohemian Rhapsody")), Karousel.key(song("Queen", "Bohemian Rhapsody - Remastered 2011")))
        XCTAssertNotEqual(Karousel.key(song("Queen", "Bohemian Rhapsody")), Karousel.key(song("Queen", "Somebody to Love")))
    }

    func testSpreadKeepsAnArtistFromPlayingTwiceInARow() {
        let spread = Karousel.spread([song("A", "1"), song("A", "2"), song("B", "1"), song("C", "1")])
        XCTAssertFalse(zip(spread, spread.dropFirst()).contains { $0.artist == $1.artist })
        XCTAssertEqual(spread.count, 4)
    }
}
