import XCTest
@testable import KultrCore

/** The same numbers every run. */
private struct Seeded: RandomNumberGenerator {
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

/** A server whose station for a song is ten songs "like" it, each by its own artist. */
@MainActor
private class LikeServer: KarouselSources {
    let favouriteSongs: [Song]
    var stations: [String] = []
    var extra: [Song] = []

    init(favourites: [Song] = []) {
        favouriteSongs = favourites
    }

    func station(_ seed: Song) async throws -> [Song] {
        stations.append(seed.id)
        return extra + (1...10).map { Song(id: "\(seed.title)-like-\($0)", title: "Like \(seed.title) \($0)", artist: "\(seed.title) artist \($0)") }
    }

    func similarArtists(_ artist: ArtistRef) async throws -> [ArtistRef] { [] }
    func topSongs(_ artist: ArtistRef, count: Int) async throws -> [Song] { [] }
    func byArtists(_ artists: [ArtistRef]) async throws -> [Song] { [] }
    func inGenres(_ genres: Set<String>, count: Int) async throws -> [Song] { [] }
    func favourites(_ count: Int) async throws -> [Song] { Array(favouriteSongs.prefix(count)) }
}

/** Suggested songs under a playlist: the same cases as Kultr for Android and the web. */
@MainActor
final class PlaylistSuggestionsTests: XCTestCase {
    private func song(_ artist: String, _ title: String, id: String? = nil) -> Song {
        Song(id: id ?? "\(artist)-\(title)", title: title, artist: artist, artistId: "ar-\(artist)")
    }

    private var playlist: [Song] {
        [song("Yll Limani", "Faaaj"), song("Yll Limani", "Taxi"), song("Majk", "Kcen"), song("Era Istrefi", "Bonbon")]
    }

    private var added: Song { song("Dhurata Dora", "NRVZ") }

    func testSeedsAreThreeArtistsWithTheSongJustAddedFirst() {
        var random = Seeded(1)
        let seeds = PlaylistSuggestions.seeds(playlist, added: nil, using: &random)
        XCTAssertEqual(seeds.count, 3)
        XCTAssertEqual(Set(seeds.map { $0.artist ?? "" }).count, 3)
        let afterAdd = PlaylistSuggestions.seeds(playlist + [added], added: added, using: &random)
        XCTAssertEqual(afterAdd.first?.id, added.id)
        XCTAssertTrue(afterAdd.dropFirst().allSatisfy { $0.id != added.id && $0.artist != added.artist })
    }

    func testNeverSuggestsThePlaylistOrTheSameSongFromAnotherAlbum() async {
        let server = LikeServer()
        server.extra = [song("Majk", "Kcen (Remastered 2024)", id: "other-album")]
        let picks = await PlaylistSuggestions.suggest(sources: server, playlist: playlist, random: Seeded(2))
        XCTAssertEqual(picks.count, PlaylistSuggestions.count)
        let ids = Set(playlist.map { $0.id })
        XCTAssertTrue(picks.allSatisfy { !ids.contains($0.id) && $0.id != "other-album" }, picks.map { $0.title }.joined(separator: ", "))
    }

    func testAfterAnAddTheSuggestionsAreLikeIt() async {
        let server = LikeServer()
        let picks = await PlaylistSuggestions.suggest(sources: server, playlist: playlist + [added], added: added, random: Seeded(4))
        XCTAssertEqual(server.stations.first, added.id)
        XCTAssertGreaterThanOrEqual(picks.filter { $0.title.hasPrefix("Like \(added.title)") }.count, 3)
    }

    func testRefreshOffersDifferentSongs() async {
        let first = await PlaylistSuggestions.suggest(sources: LikeServer(), playlist: playlist, random: Seeded(3))
        let refreshed = await PlaylistSuggestions.suggest(sources: LikeServer(), playlist: playlist, leaveOut: first, random: Seeded(3))
        XCTAssertFalse(refreshed.isEmpty)
        let shown = Set(first.map { $0.id })
        XCTAssertTrue(refreshed.allSatisfy { !shown.contains($0.id) })
    }

    func testAnEmptyPlaylistStartsFromFavourites() async {
        let favourites = [song("Capital T", "Bongo"), song("Tayna", "OMG"), song("Lluni", "Ditari")]
        let server = LikeServer(favourites: favourites)
        let picks = await PlaylistSuggestions.suggest(sources: server, playlist: [], random: Seeded(5))
        XCTAssertTrue(favourites.contains { $0.id == server.stations.first })
        XCTAssertEqual(picks.count, PlaylistSuggestions.count)
        let nothing = await PlaylistSuggestions.suggest(sources: LikeServer(), playlist: [], random: Seeded(6))
        XCTAssertTrue(nothing.isEmpty)
    }
}
