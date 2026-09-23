import XCTest
@testable import KultrCore

final class UtilTests: XCTestCase {
    func testFormatsTimes() {
        XCTAssertEqual(Format.time(nil), "0:00")
        XCTAssertEqual(Format.time(187.9), "3:07")
        XCTAssertEqual(Format.time(3723), "1:02:03")
        XCTAssertEqual(Format.duration(5040), "1 hr 24 min")
        XCTAssertEqual(Format.duration(25), "25 sec")
        XCTAssertEqual(Format.bytes(1536), "1.5 KB")
        XCTAssertEqual(Format.sortKey("The Beatles"), "beatles")
        XCTAssertEqual(Format.initials("Boards of Canada"), "BO")
        XCTAssertEqual(Format.relative(nil), "never")
        XCTAssertEqual(Format.relative(1_000, now: 1_000 + 5 * 60_000), "5 min ago")
    }

    func testStructuredSyncedLyricsWin() throws {
        let doc = try XCTUnwrap(LyricsParser.choose(
            [
                StructuredLyrics(synced: false, line: [StructuredLyricLine(value: "plain")]),
                StructuredLyrics(synced: true, offset: 500, line: [StructuredLyricLine(start: 1000, value: "a"), StructuredLyricLine(start: 3000, value: "b")]),
            ],
            plain: nil
        ))
        XCTAssertTrue(doc.synced)
        XCTAssertEqual(doc.lines[0].start, 1.5)
        XCTAssertEqual(doc.activeIndex(1.0), -1)
        XCTAssertEqual(doc.activeIndex(2.0), 0)
        XCTAssertEqual(doc.activeIndex(9.0), 1)
    }

    func testPlainTextThatIsReallyLrcIsSynced() throws {
        let doc = try XCTUnwrap(LyricsParser.choose([], plain: Lyrics(value: "[00:01.50]Hello\n[00:03.00][00:05.25]Again")))
        XCTAssertTrue(doc.synced)
        XCTAssertEqual(doc.lines.map { $0.start }, [1.5, 3.0, 5.25])
        let plain = try XCTUnwrap(LyricsParser.choose([], plain: Lyrics(value: "one\ntwo")))
        XCTAssertEqual(plain.lines.count, 2)
        XCTAssertNil(LyricsParser.choose([], plain: Lyrics(value: "  ")))
    }

    func testDominantColourIgnoresGreysAndPicksTheCommonHue() throws {
        let orange = ArtworkColor.rgb(220, 120, 40)
        let grey = ArtworkColor.rgb(128, 128, 128)
        let pixels = (0..<100).map { $0 < 60 ? orange : grey }
        let colour = try XCTUnwrap(ArtworkColor.dominant(pixels))
        XCTAssertGreaterThan(colour >> 16 & 0xff, colour & 0xff)
        XCTAssertNil(ArtworkColor.dominant(Array(repeating: grey, count: 10)))
        XCTAssertEqual(ArtworkColor.toHex(try XCTUnwrap(ArtworkColor.parseHex("#7C8CFF"))), "#7c8cff")
    }

    func testCurvesStartAndEndInTheRightPlace() {
        for curve in CrossfadeCurve.allCases {
            XCTAssertEqual(curveValue(curve, 0, rising: true), 0, accuracy: 1e-9)
            XCTAssertEqual(curveValue(curve, 1, rising: true), 1, accuracy: 1e-9)
            XCTAssertEqual(curveValue(curve, 0, rising: false), 1, accuracy: 1e-9)
            XCTAssertEqual(curveValue(curve, 1, rising: false), 0, accuracy: 1e-9)
        }
    }

    func testReplayGainNeverClips() {
        let song = Song(id: "x", replayGain: ReplayGain(trackGain: 6, albumGain: -3, trackPeak: 0.9))
        let track = replayGainFor(song, Settings().with { $0.replayGainMode = .track })
        XCTAssertEqual(track, 1 / 0.9, accuracy: 0.001)
        let album = replayGainFor(song, Settings().with { $0.replayGainMode = .album })
        XCTAssertEqual(album, 0.7079, accuracy: 0.001)
        XCTAssertEqual(replayGainFor(song, Settings().with { $0.replayGainMode = .off }), 1)
    }
}

final class DspTests: XCTestCase {
    private let rate = 22050

    /** A small deterministic generator so the click tracks are repeatable. */
    private struct SeededRandom: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    /** Short decaying noise bursts on every beat, louder on the downbeat. */
    private func clickTrack(_ bpm: Double, _ seconds: Double, introSilence: Double = 0) -> [Float] {
        var pcm = [Float](repeating: 0, count: Int(seconds * Double(rate)))
        var random = SeededRandom(state: 42)
        let beat = 60 / bpm
        var t = introSilence
        var n = 0
        while t < seconds {
            let start = Int(t * Double(rate))
            let gain = n % 4 == 0 ? 1.0 : 0.55
            for i in 0..<Int(0.06 * Double(rate)) {
                let index = start + i
                if index >= pcm.count { break }
                let env = exp(-Double(i) / (0.012 * Double(rate)))
                pcm[index] += Float((Double.random(in: -1...1, using: &random)) * env * gain)
            }
            t += beat
            n += 1
        }
        return pcm
    }

    private func tones(_ frequencies: [(Double, Double)], _ seconds: Double) -> [Float] {
        (0..<Int(seconds * Double(rate))).map { i in
            var v = 0.0
            for (hz, amp) in frequencies { v += amp * sin(2 * Double.pi * hz * Double(i) / Double(rate)) }
            return Float(v * 0.2)
        }
    }

    func testFftFindsASineInTheRightBin() {
        let size = 64
        let fft = Fft(size: size)
        var re = (0..<size).map { Float(sin(2 * Double.pi * 5 * Double($0) / Double(size))) }
        var im = [Float](repeating: 0, count: size)
        fft.transform(&re, &im)
        let mags = (0..<(size / 2)).map { (re[$0] * re[$0] + im[$0] * im[$0]).squareRoot() }
        XCTAssertEqual(mags.indices.max(by: { mags[$0] < mags[$1] }), 5)
    }

    func testDetectsTempoOfAClickTrack() {
        for bpm in [120.0, 128.0, 95.0, 174.0] {
            let result = analysePcm(clickTrack(bpm, 60), sampleRate: rate)
            XCTAssertLessThan(abs(result.bpm - bpm), 1, "expected \(bpm), got \(result.bpm)")
            XCTAssertGreaterThan(result.bpmConfidence, 0.2, "confidence \(result.bpmConfidence) at \(bpm)")
        }
    }

    func testFindsTheFirstBeatAndTheIntro() {
        let result = analysePcm(clickTrack(120, 60, introSilence: 8), sampleRate: rate)
        let phase = result.beatOffset.truncatingRemainder(dividingBy: 0.5)
        XCTAssertTrue(phase < 0.05 || phase > 0.45, "beat phase \(phase)")
        XCTAssertTrue((6.5...9.5).contains(result.introEnd), "intro end \(result.introEnd)")
    }

    func testDetectsMajorAndMinorKeys() {
        let cMajor = tones([(261.63, 1.0), (329.63, 0.8), (392.0, 0.9), (293.66, 0.3), (349.23, 0.3), (440.0, 0.3), (493.88, 0.3)], 20)
        let key = detectKey(spectralFeatures(cMajor, sampleRate: rate).chroma)
        XCTAssertEqual(key.name, "C")
        XCTAssertEqual(key.camelot, "8B")
        let aMinor = tones([(220.0, 1.0), (261.63, 0.8), (329.63, 0.9), (246.94, 0.3), (293.66, 0.3), (349.23, 0.3), (392.0, 0.3)], 20)
        let minor = detectKey(spectralFeatures(aMinor, sampleRate: rate).chroma)
        XCTAssertEqual(minor.mode, .minor)
        XCTAssertEqual(minor.camelot, "8A")
    }

    func testCamelotDistances() {
        XCTAssertEqual(camelotDistance("8A", "8A"), 0)
        XCTAssertEqual(camelotDistance("8A", "8B"), 0.5)
        XCTAssertEqual(camelotDistance("8A", "9A"), 1)
        XCTAssertEqual(camelotDistance("12B", "1B"), 1)
        XCTAssertEqual(camelotDistance("8A", "9B"), 2)
        XCTAssertEqual(camelotDistance("8A", "nonsense"), 6)
    }

    func testMonoAccumulatorDownmixesAndDecimates() {
        let acc = MonoAccumulator(inputRate: 44100, channels: 2)
        XCTAssertEqual(acc.sampleRate, 22050)
        acc.addPcm16((0..<8).map { $0 % 2 == 0 ? Int16.max : 0 })
        let out = acc.toArray()
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0], 0.5, accuracy: 0.001)
        let floats = MonoAccumulator(inputRate: 48000, channels: 1)
        XCTAssertEqual(floats.sampleRate, 24000)
        floats.addFloat(Array(repeating: 0.25, count: 10))
        XCTAssertEqual(floats.length, 5)
    }
}

final class InjektTests: XCTestCase {
    private func analysis(
        _ id: String,
        _ bpm: Double,
        camelot: String = "8A",
        energy: Double = 0.5,
        outroStart: Double = 200,
        introEnd: Double = 0,
        confidence: Double = 0.8
    ) -> TrackAnalysis {
        TrackAnalysis(
            songId: id, analysedAt: 0, bpmSource: .dsp, duration: 240, bpm: bpm, bpmConfidence: confidence,
            beatOffset: 0, downbeatOffset: 0, outroDownbeat: 0, key: 9, keyName: "Am", mode: .minor,
            keyConfidence: 0.5, camelot: camelot, energy: energy, brightness: 0.3, peak: 0.9,
            introEnd: introEnd, outroStart: outroStart
        )
    }

    private let a = Song(id: "a", title: "A", duration: 240)
    private let b = Song(id: "b", title: "B", duration: 240)
    private let context = PlanContext(durationA: 240, currentTime: 150)

    func testTempoMeetsInTheMiddle() {
        let match = matchTempo(120, 130, blend: 0.5)
        XCTAssertLessThan(abs(match.meetBpm - 124.9), 0.1)
        XCTAssertLessThan(abs(match.outgoingRate * 120 - match.incomingRate * 130), 1e-9)
        let half = matchTempo(140, 70, blend: 0)
        XCTAssertEqual(half.targetBpm, 140)
        XCTAssertEqual(half.worstShift, 0, accuracy: 1e-9)
    }

    func testWithoutInjektItIsAPlainCrossfade() {
        let s = Settings().with { $0.injektEnabled = false; $0.crossfadeSeconds = 6 }
        let plan = planTransition(current: a, next: b, context: context, settings: s, analysisA: nil, analysisB: nil)
        XCTAssertEqual(plan.type, .crossfade)
        XCTAssertEqual(plan.duration, 6)
        XCTAssertEqual(plan.startAt, 234)
        let gapless = planTransition(current: a, next: b, context: context, settings: s.with { $0.crossfadeEnabled = false }, analysisA: nil, analysisB: nil)
        XCTAssertEqual(gapless.type, .gapless)
        let cut = planTransition(current: a, next: b, context: context, settings: s.with { $0.crossfadeEnabled = false; $0.gapless = false }, analysisA: nil, analysisB: nil)
        XCTAssertEqual(cut.type, .cut)
    }

    func testCloseTempiAreBeatMatchedOnABar() {
        let plan = planTransition(current: a, next: b, context: context, settings: Settings(), analysisA: analysis("a", 124), analysisB: analysis("b", 126, camelot: "9A"))
        XCTAssertEqual(plan.type, .blend)
        XCTAssertTrue(plan.bassSwap)
        XCTAssertTrue(plan.outgoingRate > 1 && plan.incomingRate < 1)
        XCTAssertEqual(124 * plan.outgoingRate, 126 * plan.incomingRate, accuracy: 1e-6)
        let bar = 60.0 / 124 * 4
        let bars = plan.startAt / bar
        XCTAssertEqual(bars, bars.rounded(), accuracy: 1e-6)
        XCTAssertGreaterThanOrEqual(plan.startAt, context.currentTime)
        XCTAssertGreaterThan(plan.outgoingRamp, 0)
    }

    func testFarTempiClashesAndRadio() {
        let far = planTransition(current: a, next: b, context: context, settings: Settings(), analysisA: analysis("a", 100), analysisB: analysis("b", 128))
        XCTAssertEqual(far.type, .crossfade)
        let clash = planTransition(current: a, next: b, context: context, settings: Settings(), analysisA: analysis("a", 124, camelot: "8A"), analysisB: analysis("b", 124, camelot: "2B"))
        XCTAssertEqual(clash.type, .sweep)
        let radio = Song(id: "radio:1", title: "FM", kultrStreamUrl: "http://x")
        XCTAssertEqual(planTransition(current: radio, next: b, context: context, settings: Settings(), analysisA: nil, analysisB: nil).type, .cut)
        let intro = planTransition(current: a, next: b, context: context, settings: Settings(), analysisA: analysis("a", 120), analysisB: analysis("b", 120, introEnd: 17.3))
        XCTAssertGreaterThanOrEqual(intro.inStartOffset, 17.3)
    }

    func testAffinityPrefersSimilarTracks() {
        let seed = analysis("s", 124, camelot: "8A", energy: 0.6)
        let close = analysis("c", 125, camelot: "9A", energy: 0.6)
        let far = analysis("f", 90, camelot: "3B", energy: 0.1)
        XCTAssertGreaterThan(affinity(seed, close), affinity(seed, far))
        XCTAssertEqual(rankAutoQueue(seed: seed, candidates: [(Song(id: "f"), far), (Song(id: "c"), close)], count: 1).count, 1)
    }
}

final class SettingsFileTests: XCTestCase {
    func testExportRoundTrips() throws {
        let mine = Settings().with {
            $0.theme = .light
            $0.crossfadeSeconds = 9.5
            $0.homeTiles = ["radios", "recentlyAdded"]
            $0.eqGains = (0..<10).map { Double($0) }
        }
        let text = SettingsFile.export(mine, appVersion: "1.0", exportedAt: "2026-01-01T00:00:00Z")
        XCTAssertTrue(text.contains("\"kind\" : \"kultr.settings\""))
        XCTAssertFalse(text.contains("hasSeenWelcome"))
        let result = try SettingsFile.importFile(text, current: Settings())
        XCTAssertEqual(result.settings.theme, .light)
        XCTAssertEqual(result.settings.crossfadeSeconds, 9.5)
        XCTAssertEqual(result.settings.homeTiles, mine.homeTiles)
        XCTAssertEqual(result.settings.eqGains, mine.eqGains)
        XCTAssertTrue(result.servers.isEmpty)
    }

    func testAWebClientExportImportsWhatItCan() throws {
        let web = """
        {"kind":"kultr.settings","version":1,"exportedAt":"2026-01-01","app":"Kultr 1.4.0",
         "settings":{"theme":"system","glass":"frosted","crossfadeSeconds":4,"injektBars":16,
                     "eqGains":[1,2,3,4,5,6,7,8,9,10,11],"volume":0.5,"accent":42,
                     "corners":"hexagonal","password":"hunter2","homeTiles":["radios"]},
         "servers":[{"label":"Home","serverUrl":"https://nd.example.com","authMode":"token","password":"x"}]}
        """
        let result = try SettingsFile.importFile(web, current: Settings())
        XCTAssertEqual(result.settings.theme, .system)
        XCTAssertEqual(result.settings.crossfadeSeconds, 4)
        XCTAssertEqual(result.settings.injektBars, 16)
        XCTAssertEqual(result.settings.eqGains.count, 10)
        XCTAssertEqual(result.settings.homeTiles, ["radios"])
        let skipped = Dictionary(uniqueKeysWithValues: result.skipped.map { ($0.key, $0.reason) })
        XCTAssertNotNil(skipped["glass"])
        XCTAssertNotNil(skipped["volume"])
        XCTAssertEqual(skipped["accent"], "wrong type")
        XCTAssertEqual(skipped["corners"], "value not understood")
        XCTAssertNotNil(skipped["password"])
        XCTAssertEqual(result.servers.map { $0.serverUrl }, ["https://nd.example.com"])
    }

    func testGarbageIsRejected() {
        XCTAssertThrowsError(try SettingsFile.importFile("not json", current: Settings()))
        XCTAssertThrowsError(try SettingsFile.importFile("{\"kind\":\"other\"}", current: Settings()))
        XCTAssertThrowsError(try SettingsFile.importFile("{\"kind\":\"kultr.settings\",\"settings\":{\"nope\":1}}", current: Settings()))
    }

    func testHomeTilesAndEq() {
        XCTAssertEqual(resolveHomeTiles(["radios", "bogus", "radios", "recentlyAdded"]).map { $0.id }, ["radios", "recentlyAdded"])
        XCTAssertEqual(availableHomeTiles(["radios", "recentlyAdded"]).count, HOME_TILES.count - 2)
        let s = Settings().withEqPreset("Bass Boost")
        XCTAssertEqual(s.eqBandGains.count, EQ_BANDS.count)
        XCTAssertEqual(s.eqBandGains[0], 6)
        XCTAssertEqual(Settings().with { $0.eqGains = [1] }.eqBandGains.count, 10)
    }

    func testSettingsDecodeLeniently() throws {
        let json = #"{"theme":"light","crossfadeSeconds":"oops","injektBars":16.0,"unknown":true}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        XCTAssertEqual(s.theme, .light)
        XCTAssertEqual(s.crossfadeSeconds, 6)
        XCTAssertEqual(s.injektBars, 16)
    }
}

/** Answers requests from a closure instead of the network. */
final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, String))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, body) = MockURLProtocol.handler?(request) ?? (404, "")
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class SubsonicClientTests: XCTestCase {
    private static func ok(_ body: String) -> String {
        #"{"subsonic-response":{"status":"ok","version":"1.16.1","type":"navidrome","serverVersion":"0.53.3","openSubsonic":true"# + body + "}}"
    }

    private func client(user: String = "alice", mode: AuthMode = .token) -> SubsonicClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return SubsonicClient(
            credentials: Credentials(serverUrl: "https://music.example.com/nd/", username: user, password: "sesame", authMode: mode),
            session: URLSession(configuration: config)
        )
    }

    override func setUp() {
        MockURLProtocol.handler = { request in
            let ok = SubsonicClientTests.ok
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            let query = Dictionary(components.queryItems!.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
            if query["u"] == "bad" {
                return (200, #"{"subsonic-response":{"status":"failed","version":"1.16.1","error":{"code":40,"message":"Wrong username or password"}}}"#)
            }
            switch components.path.split(separator: "/").last.map(String.init) {
            case "ping": return (200, ok(""))
            case "getArtists":
                return (200, ok(#","artists":{"index":[{"name":"A","artist":[{"id":"ar1","name":"Aphex Twin","albumCount":3}]},{"name":"B","artist":[{"id":2,"name":"Boards of Canada","albumCount":"2","starred":"2024-01-01T00:00:00Z"}]}]}"#))
            case "getAlbum":
                return (200, ok(#","album":{"id":"al1","name":"SAW","songCount":2,"unknownField":{"x":1},"song":[{"id":"s1","title":"Xtal","track":1,"duration":291,"replayGain":{"trackGain":-6.5,"trackPeak":0.98}},{"id":"s2","title":"Tha","duration":544,"bpm":128},{"title":"no id"}]}"#))
            case "getAlbumList2": return (200, ok(#","albumList2":{}"#))
            case "search3": return (200, ok(#","searchResult3":{"song":{"id":"one","title":"Single"}}"#))
            default: return (404, "")
            }
        }
    }

    func testTokenMatchesTheSubsonicDocumentation() {
        XCTAssertEqual(md5Hex("sesame" + "c19b2d"), "26719a1196d2a940705a59634eb18eab")
    }

    func testBuildsUrlsUnderTheBasePath() throws {
        let url = try client().buildUrl("search3", [("query", "a+b & c"), ("songId", ["1", "2"]), ("none", nil)])
        XCTAssertTrue(url.absoluteString.hasPrefix("https://music.example.com/nd/rest/search3?"))
        XCTAssertTrue(url.absoluteString.contains("query=a%2Bb%20%26%20c"))
        XCTAssertTrue(url.absoluteString.contains("songId=1&songId=2"))
        XCTAssertFalse(url.absoluteString.contains("none="))
        let plain = try client(mode: .plain).buildUrl("ping")
        XCTAssertTrue(plain.absoluteString.contains("p=enc%3A736573616d65"))
    }

    func testDecodesLenientlyAndReportsErrors() async throws {
        let info = try await client().ping()
        XCTAssertEqual(info.summary, "Navidrome 0.53.3")
        let artists = try await client().getArtists()
        XCTAssertEqual(artists.map { $0.id }, ["ar1", "2"])
        XCTAssertEqual(artists[1].albumCount, 2)
        XCTAssertTrue(artists[1].isStarred)
        let album = try await client().getAlbum("al1")
        XCTAssertEqual(album?.song?.count, 2)
        XCTAssertEqual(album?.song?.first?.replayGain?.trackGain, -6.5)
        let empty = try await client().getAlbumList2(.newest)
        XCTAssertTrue(empty.isEmpty)
        let single = try await client().search3("x")
        XCTAssertEqual(single.song.map { $0.id }, ["one"])
        do {
            _ = try await client(user: "bad").ping()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(describeError(error), "Wrong username or password.")
        }
        XCTAssertEqual(normalizeServerUrl(" music.example.com/ "), "https://music.example.com")
        XCTAssertEqual(normalizeServerUrl("http://x:4533"), "http://x:4533")
    }
}

final class DatabaseTests: XCTestCase {
    private var path: String!

    override func setUp() {
        path = NSTemporaryDirectory() + "kultr-test-\(UUID().uuidString).sqlite"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: path)
    }

    func testMirrorsAndQueriesTheLibrary() throws {
        let db = try LibraryDatabase(path: path)
        try db.upsertArtists([Artist(id: "ar1", name: "The Beatles"), Artist(id: "ar2", name: "ABBA")])
        try db.upsertAlbums([Album(id: "al1", name: "Abbey Road", artist: "The Beatles", artistId: "ar1", genre: "Rock")])
        try db.replaceAlbumSongs([
            "al1": [
                Song(id: "s1", title: "Come Together", album: "Abbey Road", artist: "The Beatles", albumId: "al1", artistId: "ar1", track: 1, genre: "Rock", duration: 259, playCount: 3),
                Song(id: "s2", title: "Something", albumId: "al1", artistId: "ar1", track: 2, duration: 182, replayGain: ReplayGain(trackGain: -4)),
            ],
        ])
        XCTAssertEqual(db.counts().songs, 2)
        XCTAssertEqual(db.artists().map { $0.name }, ["ABBA", "The Beatles"])
        XCTAssertEqual(db.songsOfAlbum("al1").map { $0.id }, ["s1", "s2"])
        XCTAssertEqual(db.song("s2")?.replayGain?.trackGain, -4)
        XCTAssertEqual(db.searchSongs("%come%", "come%", 10).map { $0.id }, ["s1"])
        XCTAssertEqual(db.mostPlayedArtists(5).map { $0.id }, ["ar1"])

        try db.replaceAlbumSongs(["al1": [Song(id: "s1", title: "Come Together", albumId: "al1")]])
        XCTAssertNil(db.song("s2"))

        try db.setSongStarred("s1", "2026-01-01T00:00:00Z")
        XCTAssertEqual(db.starredSongs().map { $0.id }, ["s1"])

        try db.replacePlaylists([Playlist(id: "p1", name: "Mix", entry: [Song(id: "s1")])])
        XCTAssertEqual(db.playlist("p1")?.entryIds, ["s1"])

        let store = DatabaseLibraryStore(db)
        let removed = try awaitResult { try await store.deleteSongsOutsideAlbums([]) }
        XCTAssertEqual(removed, 1)

        try db.setSyncState(SyncState(lastCheck: 5, counts: LibraryCounts(songs: 7)))
        XCTAssertEqual(db.syncState().lastCheck, 5)
        XCTAssertEqual(db.syncState().counts.songs, 7)
    }

    func testDownloadsHistoryAndAnalysis() throws {
        let db = try LibraryDatabase(path: path)
        try db.upsertDownloads([
            DownloadRow(songId: "a", state: DownloadState.queued, path: nil, size: 0, contentType: nil, requestedAt: 2, savedAt: nil, error: nil),
            DownloadRow(songId: "b", state: DownloadState.done, path: "b.mp3", size: 100, contentType: nil, requestedAt: 1, savedAt: 3, error: nil),
            DownloadRow(songId: "c", state: DownloadState.failed, path: nil, size: 0, contentType: nil, requestedAt: 1, savedAt: nil, error: "x"),
        ])
        XCTAssertEqual(db.queuedCount(), 1)
        XCTAssertEqual(db.downloadUsage(), DownloadUsage(count: 1, bytes: 100))
        XCTAssertEqual(try db.requeueFailed(now: 9), 1)
        XCTAssertEqual(db.queuedDownloads(10).map { $0.songId }, ["a", "c"])

        let id = try db.insertHistory(HistoryEntry(songId: "a", playedAt: 10, seconds: 60, completed: true, source: "", submitted: false))
        XCTAssertEqual(db.unsubmittedHistory(10).map { $0.id }, [id])
        try db.markSubmitted(id)
        XCTAssertTrue(db.unsubmittedHistory(10).isEmpty)

        let analysis = TrackAnalysis(
            songId: "a", analysedAt: 1, bpmSource: .tag, duration: 200, bpm: 128, bpmConfidence: 0.8, beatOffset: 0.1,
            downbeatOffset: 0.2, outroDownbeat: 190, key: 9, keyName: "Am", mode: .minor, keyConfidence: 0.4,
            camelot: "8A", energy: 0.5, brightness: 0.3, peak: 0.9, introEnd: 8, outroStart: 180
        )
        try db.putAnalysis(analysis)
        XCTAssertEqual(db.analysis("a"), analysis)
        XCTAssertEqual(db.analysisCount(version: ANALYSIS_VERSION), 1)
    }

    /** Run an async throwing call from a synchronous test. */
    private func awaitResult<T>(_ body: @escaping () async throws -> T) throws -> T {
        let expectation = expectation(description: "async")
        var result: Result<T, Error>!
        Task {
            do { result = .success(try await body()) } catch { result = .failure(error) }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10)
        return try result.get()
    }
}

/** A map-backed store, to exercise the sync logic without SQLite. */
final class MemoryStore: LibraryStore {
    var artists: [String: Artist] = [:]
    var albums: [String: Album] = [:]
    var songs: [String: Song] = [:]
    var playlists: [Playlist] = []
    var genres: [Genre] = []
    var state = SyncState()

    func albumStamps() async throws -> [String: AlbumStamp] {
        albums.mapValues { AlbumStamp(songCount: $0.songCount, changed: $0.changed, duration: $0.duration) }
    }
    func putArtists(_ artists: [Artist]) async throws { for a in artists { self.artists[a.id] = a } }
    func putAlbums(_ albums: [Album]) async throws { for a in albums { self.albums[a.id] = a } }
    func replaceAlbumSongs(_ songsByAlbum: [String: [Song]]) async throws {
        for (albumId, list) in songsByAlbum {
            songs = songs.filter { $0.value.albumId != albumId }
            for s in list { songs[s.id] = s }
        }
    }
    func replacePlaylists(_ playlists: [Playlist]) async throws { self.playlists = playlists }
    func replaceGenres(_ genres: [Genre]) async throws { self.genres = genres }
    func deleteAlbumsNotIn(_ keep: Set<String>) async throws -> Int {
        let gone = albums.keys.filter { !keep.contains($0) }
        gone.forEach { albums[$0] = nil }
        return gone.count
    }
    func deleteArtistsNotIn(_ keep: Set<String>) async throws -> Int {
        let gone = artists.keys.filter { !keep.contains($0) }
        gone.forEach { artists[$0] = nil }
        return gone.count
    }
    func deleteSongsOutsideAlbums(_ albumIds: Set<String>) async throws -> Int {
        let gone = songs.values.filter { $0.albumId == nil || !albumIds.contains($0.albumId!) }.map { $0.id }
        gone.forEach { songs[$0] = nil }
        return gone.count
    }
    func counts() async throws -> LibraryCounts {
        LibraryCounts(artists: artists.count, albums: albums.count, songs: songs.count, playlists: playlists.count, genres: genres.count)
    }
    func syncState() async throws -> SyncState { state }
    func setSyncState(_ state: SyncState) async throws { self.state = state }
}

final class LibrarySyncTests: XCTestCase {
    override func setUp() {
        MockURLProtocol.handler = { request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            let id = components.queryItems?.first(where: { $0.name == "id" })?.value ?? ""
            let head = #"{"subsonic-response":{"status":"ok","version":"1.16.1""#
            switch components.path.split(separator: "/").last.map(String.init) {
            case "ping": return (200, head + "}}")
            case "getArtists": return (200, head + #","artists":{"index":[{"name":"A","artist":[{"id":"ar1","name":"A"}]}]}}}"#)
            case "getAlbumList2":
                return (200, head + #","albumList2":{"album":[{"id":"al1","name":"One","songCount":2,"created":"2024"},{"id":"al2","name":"Two","songCount":1,"created":"2025"}]}}}"#)
            case "getAlbum":
                let songs = id == "al1"
                    ? #"[{"id":"s1","albumId":"al1"},{"id":"s2","albumId":"al1"}]"#
                    : #"[{"id":"s3","albumId":"al2"}]"#
                return (200, head + #","album":{"id":""# + id + #"","song":"# + songs + "}}}")
            case "getPlaylists": return (200, head + #","playlists":{"playlist":[{"id":"p1","name":"Mix"}]}}}"#)
            case "getPlaylist": return (200, head + #","playlist":{"id":"p1","name":"Mix","entry":[{"id":"s1"}]}}}"#)
            case "getGenres": return (200, head + #","genres":{"genre":[{"value":"Rock","songCount":3}]}}}"#)
            default: return (404, "")
            }
        }
    }

    func testFullSyncMirrorsEverythingAndCheckIsUpToDate() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = SubsonicClient(
            credentials: Credentials(serverUrl: "https://nd.example.com", username: "u", password: "p"),
            session: URLSession(configuration: config)
        )
        let store = MemoryStore()
        let sync = LibrarySync(client: client, store: store, clock: { 1000 })
        let summary = try await sync.run(mode: .full)
        XCTAssertEqual(summary.counts, LibraryCounts(artists: 1, albums: 2, songs: 3, playlists: 1, genres: 1))
        XCTAssertEqual(summary.albumsAdded, 2)
        XCTAssertEqual(store.state.newestAlbumCreated, "2025")
        XCTAssertEqual(store.playlists.first?.entry?.map { $0.id }, ["s1"])

        let check = try await sync.run(mode: .check)
        XCTAssertTrue(check.upToDate)
        XCTAssertEqual(store.state.lastFullSync, 1000)
    }
}
