import XCTest
@testable import KultrCore

final class UtilTests: XCTestCase {
    func testReadsServerTimesWithAndWithoutFractions() {
        XCTAssertEqual(Format.isoMs("2026-09-24T10:00:00Z"), 1_790_244_000_000)
        XCTAssertEqual(Format.isoMs("2026-09-24T10:00:00.123456789Z"), 1_790_244_000_000)
        XCTAssertEqual(Format.isoMs("2026-09-24T12:00:00+02:00"), 1_790_244_000_000)
        XCTAssertNil(Format.isoMs(""))
        XCTAssertNil(Format.isoMs(nil))
    }

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
        XCTAssertEqual(ArtworkColor.parseHex("#7C8CFF"), 0xff7c_8cff)
        XCTAssertNil(ArtworkColor.parseHex("#7C8CF"))
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

    func testTagsCratesAndTheirRules() {
        var a = Annotation()
        a.addTag("Gym")
        a.addTag(" gym ")
        a.addTag("Road trip")
        XCTAssertEqual(a.tags, ["Gym", "Road trip"])
        a.removeTag("GYM")
        XCTAssertEqual(a.tags, ["Road trip"])
        XCTAssertTrue(Annotation(note: "  ").isEmpty)

        let annotations = [
            Annotation.albumKey("al1"): Annotation(tags: ["Gym"]),
            Annotation.artistKey("ar2"): Annotation(note: "Loud", tags: ["gym", "Night"]),
        ]
        XCTAssertEqual(tagCounts(annotations).first?.tag.lowercased(), "gym")
        XCTAssertEqual(tagCounts(annotations).first?.count, 2)
        XCTAssertEqual(taggedIds(annotations, tags: ["GYM"]), ["al1", "ar2"])

        let gym = Station(name: "Gym", tags: ["gym"])
        let tagged = taggedIds(annotations, tags: gym.tags!)
        XCTAssertTrue(gym.matches(Song(id: "s", albumId: "al1"), nil, tagged: tagged))
        XCTAssertTrue(gym.matches(Song(id: "t", albumId: "al9", artistId: "ar2"), nil, tagged: tagged))
        XCTAssertFalse(gym.matches(Song(id: "u", albumId: "al9"), nil, tagged: tagged))

        let recent = Station(name: "New", addedDays: 30)
        let since = addedSinceDay(30, now: Date(timeIntervalSince1970: Double(Format.isoMs("2026-11-02T00:00:00Z")!) / 1000))
        XCTAssertEqual(since, "2026-10-03")
        XCTAssertTrue(recent.matches(Song(id: "n", created: "2026-10-20T10:00:00Z"), nil, addedSince: since))
        XCTAssertFalse(recent.matches(Song(id: "o", created: "2025-01-01T10:00:00Z"), nil, addedSince: since))
        XCTAssertEqual(Station(name: "Year", minRating: 4, addedDays: 365).summary, "4★ and up · added this year")

        var crate = Crate(name: "Gym")
        crate.toggle(album: "al1")
        crate.toggle(song: "s1")
        crate.toggle(song: "s2")
        crate.toggle(song: "s1")
        XCTAssertEqual(crate.contents, "1 album · 1 track")
        XCTAssertTrue(crate.contains(song: "s2"))
        let decoded = try? JSONDecoder().decode(Crate.self, from: Data(#"{"id":"c","name":"Old"}"#.utf8))
        XCTAssertEqual(decoded?.albums, [])
        XCTAssertFalse(decoded?.byRules ?? true)
    }

    func testMonthRecapCountsOneMonth() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        func play(_ id: String, _ at: String, _ seconds: Int) -> HistoryEntry {
            HistoryEntry(songId: id, playedAt: Format.isoMs(at)!, seconds: seconds, completed: true, source: "", submitted: true)
        }
        let songs = [
            "a": Song(id: "a", title: "A", album: "One", artist: "Ann", albumId: "al1", artistId: "ar1"),
            "b": Song(id: "b", title: "B", album: "One", artist: "Ann", albumId: "al1", artistId: "ar1"),
            "c": Song(id: "c", title: "C", album: "Two", artist: "Bo", albumId: "al2", artistId: "ar2"),
        ]
        let history = [
            play("a", "2026-09-20T10:00:00Z", 100),
            play("a", "2026-10-01T09:00:00Z", 200),
            play("a", "2026-10-03T09:00:00Z", 200),
            play("b", "2026-10-03T12:00:00Z", 180),
            play("c", "2026-10-15T12:00:00Z", 240),
            play("gone", "2026-10-16T12:00:00Z", 60),
            play("c", "2026-11-01T00:00:00Z", 240),
        ]
        XCTAssertEqual(recapMonths(history, calendar: utc).map { Format.iso(Int64($0.timeIntervalSince1970 * 1000)) },
                       ["2026-11-01T00:00:00Z", "2026-10-01T00:00:00Z", "2026-09-01T00:00:00Z"])
        let october = monthRecap(history, songs: songs, month: Date(timeIntervalSince1970: Double(Format.isoMs("2026-10-20T00:00:00Z")!) / 1000), calendar: utc)
        XCTAssertEqual(october.plays, 5)
        XCTAssertEqual(october.seconds, 880)
        XCTAssertEqual(october.tracks, 4)
        XCTAssertEqual(october.artists, 2)
        XCTAssertEqual(october.topSongs.map { $0.item.id }, ["a", "c", "b"])
        XCTAssertEqual(october.topSongs.first?.plays, 2)
        XCTAssertEqual(october.topArtists.map { $0.item.name }, ["Ann", "Bo"])
        XCTAssertEqual(october.topAlbums.map { $0.item.id }, ["al1", "al2"])
        XCTAssertEqual(october.busiestDay?.seconds, 380)
        XCTAssertEqual(october.firstListens, 3)
        XCTAssertEqual(october.previousSeconds, 100)
        XCTAssertTrue(monthRecap(history, songs: songs, month: Date(timeIntervalSince1970: 0), calendar: utc).isEmpty)
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
        acc.addFloat((0..<8).map { $0 % 2 == 0 ? 1 : 0 })
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

    func testTheNextTrackIsMatchedToTheTempoPlaying() {
        let match = matchTempo(124, 126)
        XCTAssertEqual(126 * match.rate, 124, accuracy: 1e-9)
        XCTAssertEqual(match.shift, 2.0 / 126, accuracy: 1e-9)
        // Half and double time count: 70 BPM is matched at 140, unchanged.
        let half = matchTempo(140, 70)
        XCTAssertEqual(half.rate, 1, accuracy: 1e-9)
        XCTAssertEqual(half.shift, 0, accuracy: 1e-9)
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
        let bar = 60.0 / 124 * 4
        let bars = plan.startAt / bar
        XCTAssertEqual(bars, bars.rounded(), accuracy: 1e-6)
        XCTAssertGreaterThanOrEqual(plan.startAt, context.currentTime)
    }

    func testSteadyTempoNeverChangesAPlayingTrack() {
        var steady = context
        let plan = planTransition(current: a, next: b, context: steady, settings: Settings(), analysisA: analysis("a", 124), analysisB: analysis("b", 126, camelot: "9A"))
        XCTAssertEqual(plan.type, .blend)
        // The playing track keeps its speed; the next one starts at its tempo and stays there.
        XCTAssertEqual(plan.outgoingRate, 1, accuracy: 1e-9)
        XCTAssertEqual(126 * plan.incomingRate, 124, accuracy: 1e-6)
        // A track an earlier blend left faster keeps that speed, and the next one meets it there.
        steady.outgoingRate = 1.02
        let carried = planTransition(current: a, next: b, context: steady, settings: Settings(), analysisA: analysis("a", 124), analysisB: analysis("b", 126, camelot: "9A"))
        XCTAssertEqual(carried.outgoingRate, 1.02, accuracy: 1e-9)
        XCTAssertEqual(126 * carried.incomingRate, 124 * 1.02, accuracy: 1e-6)
        // Further apart than the maximum shift from where the music is now: no beat-match.
        steady.outgoingRate = 1.07
        let far = planTransition(current: a, next: b, context: steady, settings: Settings(), analysisA: analysis("a", 124), analysisB: analysis("b", 120, camelot: "9A"))
        XCTAssertEqual(far.type, .crossfade)
        XCTAssertEqual(far.incomingRate, 1)
        XCTAssertEqual(far.outgoingRate, 1.07, accuracy: 1e-9)
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

    func testBeatGridFindsTheDownbeats() {
        var a = analysis("a", 120)
        a.downbeatOffset = 0.5
        let grid = BeatGrid(a)!
        XCTAssertEqual(grid.bar, 2, accuracy: 0.0001)
        XCTAssertEqual(grid.sinceDownbeat(0.5), 0, accuracy: 0.0001)
        XCTAssertEqual(grid.sinceDownbeat(3.0), 0.5, accuracy: 0.0001)
        XCTAssertEqual(grid.untilDownbeat(3.0), 1.5, accuracy: 0.0001)
        XCTAssertEqual(grid.untilDownbeat(0.2), 0.3, accuracy: 0.0001)
        XCTAssertEqual(grid.pulse(4.5), 1, accuracy: 0.0001)
        XCTAssertLessThan(grid.pulse(4.9), 0.02)
        XCTAssertEqual(grid.pulse(0.1), 0)
        XCTAssertNil(BeatGrid(analysis("b", 120, confidence: 0.1)))
    }

    func testStationsMatchTheirRules() {
        let drive = STATION_PRESETS.first { $0.id == "night-drive" }!
        let fits = analysis("a", 100, energy: 0.5)
        let tooFast = analysis("b", 128, energy: 0.5)
        XCTAssertTrue(drive.matches(Song(id: "a"), fits))
        XCTAssertFalse(drive.matches(Song(id: "b"), tooFast))
        XCTAssertFalse(drive.matches(Song(id: "c"), nil), "energy needs analysis")
        let tagged = Station(name: "Tempo only", bpm: Bounds(90, 110))
        XCTAssertTrue(tagged.matches(Song(id: "d", bpm: 100), nil), "a tempo tag is enough")
        let nineties = Station.decade(1990)
        XCTAssertTrue(nineties.matches(Song(id: "e", year: 1994), nil))
        XCTAssertFalse(nineties.matches(Song(id: "f", year: 2001), nil))
        let rock = Station(name: "Rock", genres: ["Rock"])
        XCTAssertTrue(rock.matches(Song(id: "g", genre: "Indie Rock"), nil))
        XCTAssertFalse(rock.matches(Song(id: "h", genre: "Jazz"), nil))
        XCTAssertFalse(Station(name: "New", unplayed: true).matches(Song(id: "i", playCount: 3), nil))
        XCTAssertEqual(drive.summary, "88–112 BPM · energy 4–7")
        XCTAssertEqual(Station(name: "All").summary, "Your whole library")
        XCTAssertEqual(decadeStations(Array(repeating: 1995, count: 25) + [2004, 2005]).map { $0.name }, ["1990s"])

        let decoded = try? JSONDecoder().decode(Station.self, from: Data(#"{"id":"x","name":"Old","bpm":{"min":100}}"#.utf8))
        XCTAssertEqual(decoded?.bpm?.min, 100)
        XCTAssertFalse(decoded?.unplayed ?? true)
    }

    func testStationPicksSkipWhatPlayedUntilNothingIsLeft() {
        var random = SystemRandomNumberGenerator()
        let pool: [(Song, TrackAnalysis?)] = [(Song(id: "a"), nil), (Song(id: "b"), nil)]
        let picks = stationPicks(pool: pool, seed: nil, exclude: ["a"], queued: [], count: 5, random: &random)
        XCTAssertEqual(picks.map { $0.id }, ["b"])
        let again = stationPicks(pool: pool, seed: nil, exclude: ["a", "b"], queued: ["b"], count: 5, random: &random)
        XCTAssertEqual(again.map { $0.id }, ["a"])
    }

    func testEnergyPlanFollowsTheLine() {
        var random = SystemRandomNumberGenerator()
        let candidates: [(Song, TrackAnalysis)] = (0..<20).map { i in
            (Song(id: "t\(i)", artistId: "ar\(i)"), analysis("t\(i)", 120, energy: Double(i) / 20))
        }
        let set = planSet(curve: .build, minutes: 40, candidates: candidates, random: &random)
        XCTAssertGreaterThanOrEqual(set.count, 9)
        XCTAssertLessThan(set.first!.energy, set.last!.energy)
        XCTAssertEqual(Set(set.map { $0.song.id }).count, set.count)
        XCTAssertEqual(EnergyCurve.build.value(at: 0.5), 0.625, accuracy: 0.001)
        XCTAssertEqual(EnergyCurve([0.2]).points, [0.5, 0.5])
    }

    func testCommandsFromPlainWords() {
        let stations = ["Night Drive", "Warm Up"]
        XCTAssertEqual(parseCommand("Play Night Drive", stations: stations), .station("Night Drive"))
        XCTAssertEqual(parseCommand("play radiohead"), .play("radiohead"))
        XCTAssertEqual(parseCommand("Shuffle Daft Punk!"), .shuffle("daft punk"))
        XCTAssertEqual(parseCommand("sleep in 30 minutes"), .sleep(minutes: 30))
        XCTAssertEqual(parseCommand("stop in an hour"), .sleep(minutes: 60))
        XCTAssertEqual(parseCommand("timer 1h"), .sleep(minutes: 60))
        XCTAssertEqual(parseCommand("sleep after this song"), .sleepAfterTrack)
        XCTAssertEqual(parseCommand("next"), .next)
        XCTAssertEqual(parseCommand("Shuffle all"), .shuffleAll)
        XCTAssertEqual(parseCommand("pause"), .pause)
        XCTAssertEqual(parseCommand("open settings"), .open(.settings))
        XCTAssertEqual(parseCommand("show my stations"), .open(.stations))
        XCTAssertEqual(parseCommand("plan an hour"), .plan(minutes: 60))
        XCTAssertEqual(parseCommand("plan a set"), .plan(minutes: nil))
        XCTAssertEqual(parseCommand("tune in to warm up", stations: stations), .station("Warm Up"))
        XCTAssertEqual(parseCommand("open gym", crates: ["Gym"]), .crate("Gym"))
        XCTAssertEqual(parseCommand("play gym", crates: ["Gym"]), .playCrate("Gym"))
        XCTAssertNil(parseCommand("radiohead"))
        XCTAssertNil(parseCommand("love"))
    }

    func testCommandsInGerman() {
        let stations = ["Night Drive", "Nachtfahrt"]
        XCTAssertEqual(parseCommand("Spiele Nachtfahrt", stations: stations), .station("Nachtfahrt"))
        XCTAssertEqual(parseCommand("spiel radiohead ab"), .play("radiohead"))
        XCTAssertEqual(parseCommand("spiele etwas von Daft Punk"), .play("daft punk"))
        XCTAssertEqual(parseCommand("Zufällig Daft Punk"), .shuffle("daft punk"))
        XCTAssertEqual(parseCommand("alles zufällig"), .shuffleAll)
        XCTAssertEqual(parseCommand("Schlaf in 30 Minuten"), .sleep(minutes: 30))
        XCTAssertEqual(parseCommand("stopp in einer Stunde"), .sleep(minutes: 60))
        XCTAssertEqual(parseCommand("schlaftimer 2 stunden"), .sleep(minutes: 120))
        XCTAssertEqual(parseCommand("nach diesem Titel stoppen"), .sleepAfterTrack)
        XCTAssertEqual(parseCommand("weiter"), .next)
        XCTAssertEqual(parseCommand("zurück"), .previous)
        XCTAssertEqual(parseCommand("jetzt mischen"), .mixNow)
        XCTAssertEqual(parseCommand("Öffne Einstellungen"), .open(.settings))
        XCTAssertEqual(parseCommand("zeig meine Kisten"), .open(.crates))
        XCTAssertEqual(parseCommand("geh zum Monatsrückblick"), .open(.recap))
        XCTAssertEqual(parseCommand("plane eine Stunde"), .plan(minutes: 60))
        XCTAssertEqual(parseCommand("Set planen"), .plan(minutes: nil))
        XCTAssertEqual(parseCommand("öffne Training", crates: ["Training"]), .crate("Training"))
        XCTAssertEqual(parseCommand("pause"), .pause)
    }

    func testStudioTemplatesStylesAndWidgets() {
        let values = ["year": "2019", "genre": "", "format": "FLAC", "bitrate": "1024"]
        XCTAssertEqual(renderTemplate("{year}{?genre: · {genre}} · {format}{?bitrate: · {bitrate} kbps}", values), "2019 · FLAC · 1024 kbps")
        XCTAssertEqual(renderTemplate("{?genre:only {genre}}", values), "")
        XCTAssertEqual(renderTemplate("plain {unknown}text", values), "plain text")
        XCTAssertEqual(renderTemplate("open {brace", values), "open {brace")

        let console = STUDIO_PRESETS.first { $0.name == "Console" }!
        let applied = console.applied(to: Settings())
        XCTAssertEqual(applied.corners, .sharp)
        XCTAssertEqual(applied.playerBlocks.first, .title)
        XCTAssertTrue(console.matches(applied))
        XCTAssertFalse(console.matches(Settings()))
        XCTAssertEqual(StudioStyle.read(console.link), console)
        let fromFile = StudioStyle.read(#"{"name":"Mine","corners":"round"}"#)
        XCTAssertEqual(fromFile?.corners, .round)
        XCTAssertEqual(fromFile?.playerBlocks, PlayerBlock.allCases)
        XCTAssertNil(StudioStyle.read("kultr://style/not-base64!"))

        let widgets = [
            HomeWidget(kind: .listening, size: .small),
            HomeWidget(kind: .nowPlaying, size: .medium),
            HomeWidget(kind: .nextMix, size: .small),
            HomeWidget(kind: .station, size: .small),
            HomeWidget(kind: .crate, size: .small),
        ]
        XCTAssertEqual(homeWidgetRows(widgets), [[0], [1], [2, 3], [4]])
    }

    func testCalmestFirstPutsQuietSlowTracksFirst() {
        let loud = analysis("loud", 128, energy: 0.9)
        let quiet = analysis("quiet", 80, energy: 0.2)
        XCTAssertLessThan(calmness(quiet), calmness(loud))
        XCTAssertEqual(calmness(nil), 0.5)
        let table = ["loud": loud, "quiet": quiet]
        let order = calmestFirst([Song(id: "loud"), Song(id: "unknown"), Song(id: "quiet")]) { table[$0.id] }
        XCTAssertEqual(order.map { $0.id }, ["quiet", "unknown", "loud"])
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
            $0.nightMode = true
            $0.crossfadeSeconds = 9.5
            $0.homeTiles = ["radios", "recentlyAdded"]
            $0.eqGains = (0..<10).map { Double($0) }
        }
        let text = SettingsFile.export(mine, appVersion: "1.0", exportedAt: "2026-01-01T00:00:00Z")
        XCTAssertTrue(text.contains("\"kind\" : \"kultr.settings\""))
        XCTAssertFalse(text.contains("hasSeenWelcome"))
        let result = try SettingsFile.importFile(text, current: Settings())
        XCTAssertEqual(result.settings.theme, .light)
        XCTAssertTrue(result.settings.nightMode)
        XCTAssertFalse(Settings().nightMode)
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

    func testRediscoverFindsLovedAlbumsNotPlayedForAYear() throws {
        let db = try LibraryDatabase(path: path)
        let now = Format.isoMs("2026-11-02T00:00:00Z")!
        let yearAgo = now - 365 * 86_400_000
        try db.upsertAlbums([
            Album(id: "old", name: "Old favourite", playCount: 12, played: "2024-05-01T10:00:00.123Z"),
            Album(id: "recent", name: "On repeat", playCount: 30, played: "2026-10-30T10:00:00Z"),
            Album(id: "hearted", name: "Hearted, never played", starred: "2023-01-01T00:00:00Z"),
            Album(id: "phone", name: "Played on this phone", playCount: 5, played: "2024-01-01T00:00:00Z"),
            Album(id: "once", name: "Played once", playCount: 1, played: "2020-01-01T00:00:00Z"),
        ])
        try db.replaceAlbumSongs(["phone": [Song(id: "p1", title: "One", albumId: "phone")]])
        _ = try db.insertHistory(HistoryEntry(songId: "p1", playedAt: now - 86_400_000, seconds: 200, completed: true, source: "test", submitted: true))
        XCTAssertEqual(db.forgottenAlbums(before: yearAgo, 10).map { $0.id }, ["old", "hearted"])
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

/** A map-backed store, to exercise the sync logic without SQLite. Safe to call from parallel readers. */
final class MemoryStore: LibraryStore, @unchecked Sendable {
    private let lock = NSLock()
    var artists: [String: Artist] = [:]
    var albums: [String: Album] = [:]
    var songs: [String: Song] = [:]
    var playlists: [Playlist] = []
    var genres: [Genre] = []
    var state = SyncState()

    func albumStamps() async throws -> [String: AlbumStamp] {
        lock.withLock {
            albums.mapValues {
                AlbumStamp(songCount: $0.songCount, changed: $0.changed, duration: $0.duration, playCount: $0.playCount, played: $0.played)
            }
        }
    }
    func putArtists(_ artists: [Artist]) async throws { lock.withLock { for a in artists { self.artists[a.id] = a } } }
    func putAlbums(_ albums: [Album]) async throws {
        lock.withLock {
            for a in albums {
                var copy = a
                copy.song = nil
                self.albums[a.id] = copy
            }
        }
    }
    func replaceAlbumSongs(_ songsByAlbum: [String: [Song]]) async throws {
        lock.withLock {
            for (albumId, list) in songsByAlbum {
                songs = songs.filter { $0.value.albumId != albumId }
                for s in list { songs[s.id] = s }
            }
        }
    }
    func replacePlaylists(_ playlists: [Playlist]) async throws { lock.withLock { self.playlists = playlists } }
    func replaceGenres(_ genres: [Genre]) async throws { lock.withLock { self.genres = genres } }
    func deleteAlbumsNotIn(_ keep: Set<String>) async throws -> Int {
        lock.withLock {
            let gone = albums.keys.filter { !keep.contains($0) }
            gone.forEach { albums[$0] = nil }
            return gone.count
        }
    }
    func deleteArtistsNotIn(_ keep: Set<String>) async throws -> Int {
        lock.withLock {
            let gone = artists.keys.filter { !keep.contains($0) }
            gone.forEach { artists[$0] = nil }
            return gone.count
        }
    }
    func deleteSongsOutsideAlbums(_ albumIds: Set<String>) async throws -> Int {
        lock.withLock {
            let gone = songs.values.filter { $0.albumId == nil || !albumIds.contains($0.albumId!) }.map { $0.id }
            gone.forEach { songs[$0] = nil }
            return gone.count
        }
    }
    func counts() async throws -> LibraryCounts {
        lock.withLock {
            LibraryCounts(artists: artists.count, albums: albums.count, songs: songs.count, playlists: playlists.count, genres: genres.count)
        }
    }
    func syncState() async throws -> SyncState { lock.withLock { state } }
    func setSyncState(_ state: SyncState) async throws { lock.withLock { self.state = state } }
}

/** What the mock server holds: albums, their tracks, and how often each was played. */
private final class FakeServer: @unchecked Sendable {
    private let lock = NSLock()
    /** Album id → (changed, track ids). */
    let library: [(id: String, changed: String, songs: [String])] = [
        ("al1", "t1", ["s1", "s2"]),
        ("al2", "t1", ["s3"]),
    ]
    /** Album id → (play count, last played), as the server counts them. */
    private var playsValue: [String: (Int, String)] = [:]
    private var requests: [String] = []

    var plays: [String: (Int, String)] {
        get { lock.withLock { playsValue } }
        set { lock.withLock { playsValue = newValue } }
    }

    var albumRequests: [String] { lock.withLock { requests.sorted() } }
    func clearRequests() { lock.withLock { requests = [] } }

    func respond(_ request: URLRequest) -> (Int, String) {
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        func query(_ name: String) -> String? { components.queryItems?.first(where: { $0.name == name })?.value }
        let head = #"{"subsonic-response":{"status":"ok","version":"1.16.1""#
        let plays = self.plays
        switch components.path.split(separator: "/").last.map(String.init) {
        case "ping": return (200, head + "}}")
        case "getArtists": return (200, head + #","artists":{"index":[{"name":"A","artist":[{"id":"ar1","name":"A"}]}]}}}"#)
        case "getAlbumList2":
            // "recent" lists only played albums, most recently played first.
            let recent = query("type") == "recent"
            let entries = recent
                ? library.filter { plays[$0.id] != nil }.sorted { plays[$0.id]!.1 > plays[$1.id]!.1 }
                : library
            let offset = Int(query("offset") ?? "0") ?? 0
            let albums = offset > 0 ? "" : entries.map { entry -> String in
                let played = plays[entry.id].map { #","playCount":\#($0.0),"played":"\#($0.1)""# } ?? ""
                return #"{"id":"\#(entry.id)","name":"Album \#(entry.id)","artistId":"ar1","songCount":\#(entry.songs.count),"changed":"\#(entry.changed)","created":"2026-0\#(entry.id.suffix(1))-01"\#(played)}"#
            }.joined(separator: ",")
            return (200, head + #","albumList2":{"album":["# + albums + "]}}}")
        case "getAlbum":
            let id = query("id") ?? ""
            lock.withLock { requests.append(id) }
            let count = plays[id]?.0 ?? 0
            let songs = (library.first { $0.id == id }?.songs ?? []).map {
                #"{"id":"\#($0)","title":"\#($0)","albumId":"\#(id)","playCount":\#(count)}"#
            }.joined(separator: ",")
            return (200, head + #","album":{"id":"\#(id)","name":"Album \#(id)","song":["# + songs + "]}}}")
        case "getPlaylists": return (200, head + #","playlists":{"playlist":[{"id":"p1","name":"Mix"}]}}}"#)
        case "getPlaylist": return (200, head + #","playlist":{"id":"p1","name":"Mix","entry":[{"id":"s1"}]}}}"#)
        case "getGenres": return (200, head + #","genres":{"genre":[{"value":"Rock","songCount":3}]}}}"#)
        default: return (404, "")
        }
    }
}

final class LibrarySyncTests: XCTestCase {
    private let server = FakeServer()

    override func setUp() {
        let server = self.server
        MockURLProtocol.handler = { server.respond($0) }
    }

    private func client() -> SubsonicClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return SubsonicClient(
            credentials: Credentials(serverUrl: "https://nd.example.com", username: "u", password: "p"),
            session: URLSession(configuration: config)
        )
    }

    private func sync(_ store: MemoryStore) -> LibrarySync {
        LibrarySync(client: client(), store: store, clock: { 1000 })
    }

    func testFullSyncMirrorsEverythingAndCheckIsUpToDate() async throws {
        let store = MemoryStore()
        let summary = try await sync(store).run(mode: .full)
        XCTAssertEqual(summary.counts, LibraryCounts(artists: 1, albums: 2, songs: 3, playlists: 1, genres: 1))
        XCTAssertEqual(summary.albumsAdded, 2)
        XCTAssertEqual(store.state.newestAlbumCreated, "2026-02-01")
        XCTAssertEqual(store.playlists.first?.entry?.map { $0.id }, ["s1"])

        server.clearRequests()
        let check = try await sync(store).run(mode: .check)
        XCTAssertTrue(check.upToDate)
        XCTAssertTrue(server.albumRequests.isEmpty)
        XCTAssertEqual(store.state.lastFullSync, 1000)
    }

    func testCheckRereadsAlbumsPlayedSinceWithoutCallingThemChanged() async throws {
        let store = MemoryStore()
        _ = try await sync(store).run(mode: .full)
        server.clearRequests()

        server.plays = ["al2": (4, "2026-09-24T10:00:00Z")]
        let summary = try await sync(store).run(mode: .check)
        XCTAssertEqual(server.albumRequests, ["al2"])
        XCTAssertEqual(summary.albumsPlayed, 1)
        XCTAssertEqual(summary.albumsUpdated, 0)
        XCTAssertTrue(summary.upToDate)
        XCTAssertEqual(store.songs["s3"]?.playCount, 4)
    }

    func testListeningPullReadsBackOnlyAlbumsPlayedSince() async throws {
        let store = MemoryStore()
        server.plays = ["al1": (2, "2026-09-20T08:00:00Z")]
        _ = try await sync(store).run(mode: .full)
        server.clearRequests()

        // Played elsewhere: al2 for the first time, al1 not again.
        server.plays = ["al1": (2, "2026-09-20T08:00:00Z"), "al2": (1, "2026-09-24T09:00:00Z")]
        let listening = ListeningSync(client: client(), store: store)
        let pull = try await listening.pull()
        XCTAssertEqual(pull.albumsChanged, 1)
        XCTAssertEqual(server.albumRequests, ["al2"])
        XCTAssertEqual(store.songs["s3"]?.playCount, 1)
        XCTAssertEqual(store.albums["al2"]?.played, "2026-09-24T09:00:00Z")
        XCTAssertEqual(store.state.listeningPulledThrough, "2026-09-24T09:00:00Z")

        // Nothing new: nothing re-read.
        server.clearRequests()
        let again = try await listening.pull()
        XCTAssertEqual(again.albumsChanged, 0)
        XCTAssertTrue(server.albumRequests.isEmpty)

        // A later library sync keeps the watermark.
        _ = try await sync(store).run(mode: .check)
        XCTAssertEqual(store.state.listeningPulledThrough, "2026-09-24T09:00:00Z")
    }
}
