import Foundation

enum ThemeMode: String, Codable, CaseIterable, Hashable {
    case dark, light, system
}

enum AccentMode: String, Codable, CaseIterable, Hashable {
    case artwork, fixed
}

enum SurfaceBorder: String, Codable, CaseIterable, Hashable {
    case neutral, accent
}

enum CornerStyle: String, Codable, CaseIterable, Hashable {
    case sharp, soft, round
}

enum PlayheadStyle: String, Codable, CaseIterable, Hashable {
    case minimal, glow, pulse, wave, comet, equalizer

    var label: String {
        switch self {
        case .minimal: return "Minimal"
        case .glow: return "Glow"
        case .pulse: return "Pulse"
        case .wave: return "Wave"
        case .comet: return "Comet"
        case .equalizer: return "Equalizer"
        }
    }

    var note: String {
        switch self {
        case .minimal: return "A plain accent-coloured bar. Still."
        case .glow: return "A soft halo that breathes around the playhead."
        case .pulse: return "A ring that expands out of the playhead in time."
        case .wave: return "Diagonal light travelling along the played part."
        case .comet: return "A bright head dragging a shimmering tail."
        case .equalizer: return "Sliding bars, like a level meter."
        }
    }
}

enum GridSize: String, Codable, CaseIterable, Hashable {
    case small, medium, large
}

enum CrossfadeCurve: String, Codable, CaseIterable, Hashable {
    case equalPower, linear, smooth, sharp

    var label: String {
        switch self {
        case .equalPower: return "Equal power"
        case .linear: return "Linear"
        case .smooth: return "Smooth"
        case .sharp: return "Sharp"
        }
    }
}

enum ReplayGainMode: String, Codable, CaseIterable, Hashable {
    case off, track, album

    var label: String {
        switch self {
        case .off: return "Off"
        case .track: return "Per track"
        case .album: return "Per album"
        }
    }
}

let EQ_BANDS: [Int] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

/** Equaliser presets, in the order they are offered. */
let EQ_PRESET_LIST: [(name: String, gains: [Double])] = [
    ("Flat", [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
    ("Bass Boost", [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
    ("Bass Reduce", [-6, -5, -4, -2, 0, 0, 0, 0, 0, 0]),
    ("Treble Boost", [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]),
    ("Vocal", [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1]),
    ("Acoustic", [4, 3, 2, 0, 1, 1, 2, 3, 3, 2]),
    ("Electronic", [5, 4, 1, 0, -2, 1, 0, 2, 4, 5]),
    ("Late Night", [-4, -3, -1, 1, 2, 2, 1, 0, -1, -2]),
    ("Loudness", [6, 4, 0, -2, -3, -1, 1, 3, 5, 6]),
]

let EQ_PRESETS: [String: [Double]] = Dictionary(uniqueKeysWithValues: EQ_PRESET_LIST.map { ($0.name, $0.gains) })

/**
 * Every preference Kultr has. Key names match the web client's, so a settings
 * file exported from one can be imported into the other; anything only one
 * side understands is skipped on import rather than guessed at.
 */
struct Settings: Codable, Hashable {
    // ---- appearance
    var theme: ThemeMode = .dark
    var accentMode: AccentMode = .artwork
    var accent: String = "#7c8cff"
    /** How strongly `accent` is mixed into the colour taken from the artwork, 0–100. */
    var accentBlend: Int = 0
    var surfaceBorder: SurfaceBorder = .accent
    var borderOpacity: Int = 45
    var surfaceOpacity: Int = 100
    var corners: CornerStyle = .soft
    var playhead: PlayheadStyle = .minimal
    /** Whether the player's left-hand time counts up or down. */
    var timeRemaining: Bool = false
    var reduceMotion: Bool = false
    var backdropArtwork: Bool = true
    var gridSize: GridSize = .medium
    var compactRows: Bool = false

    // ---- playback
    var crossfadeEnabled: Bool = true
    var crossfadeSeconds: Double = 6.0
    var crossfadeCurve: CrossfadeCurve = .equalPower
    var crossfadeOnSkip: Bool = true
    var gapless: Bool = true
    var replayGainMode: ReplayGainMode = .track
    var replayGainPreamp: Double = 0.0
    /** kbps cap on Wi-Fi; 0 streams the original file. */
    var preferredBitrate: Int = 0
    /** kbps cap on mobile data; -1 means "same as Wi-Fi". */
    var preferredBitrateMobile: Int = -1
    var preferredFormat: String = ""
    var scrobble: Bool = true
    var resumeOnStart: Bool = true

    // ---- equaliser
    var eqEnabled: Bool = false
    var eqPreset: String = "Flat"
    var eqGains: [Double] = Array(repeating: 0, count: 10)
    var eqPreamp: Double = 0.0

    // ---- injekt
    var injektEnabled: Bool = true
    var injektBeatMatch: Bool = true
    var injektBassSwap: Bool = true
    var injektHarmonic: Bool = true
    var injektMaxTempoShift: Double = 8.0
    /** Ease the *current* track toward the next one's tempo before the blend. */
    var injektTempoRamp: Bool = true
    /** Share of the tempo gap the current track closes, 0–100. */
    var injektTempoBlend: Double = 50.0
    var injektBars: Int = 8
    var injektSkipIntro: Bool = true
    var injektAutoQueue: Bool = true
    var injektAnalyseAhead: Bool = true
    /** Only analyse over Wi-Fi, so InjeKt never spends mobile data. */
    var injektAnalyseOnWifiOnly: Bool = false

    // ---- offline
    var offlineConcurrency: Int = 3
    /** kbps for downloads; 0 keeps the original file. */
    var offlineBitrate: Int = 0
    var offlineWifiOnly: Bool = true
    /** Play a downloaded file instead of streaming when one exists. */
    var offlineFirst: Bool = true
    /** Size of the cache for streamed audio, in MB. */
    var streamCacheMb: Int = 1024

    // ---- library
    var autoSyncOnStart: Bool = true
    var autoSyncMinutes: Int = 60
    var syncPlaylistContents: Bool = true

    // ---- misc
    var showLyrics: Bool = true
    /** Which shelves the home page shows, in order. Ids come from [HOME_TILES]. */
    var homeTiles: [String] = ["mostPlayedSongs", "mostPlayedAlbums", "randomSongs", "mostPlayedArtists"]
    /** Radio stations you have hearted. Navidrome has no concept of this. */
    var favouriteRadios: [String] = []
    var hasSeenWelcome: Bool = false

    init() {}

    enum CodingKeys: String, CodingKey, CaseIterable {
        case theme, accentMode, accent, accentBlend, surfaceBorder, borderOpacity, surfaceOpacity, corners
        case playhead, timeRemaining, reduceMotion, backdropArtwork, gridSize, compactRows
        case crossfadeEnabled, crossfadeSeconds, crossfadeCurve, crossfadeOnSkip, gapless, replayGainMode
        case replayGainPreamp, preferredBitrate, preferredBitrateMobile, preferredFormat, scrobble, resumeOnStart
        case eqEnabled, eqPreset, eqGains, eqPreamp
        case injektEnabled, injektBeatMatch, injektBassSwap, injektHarmonic, injektMaxTempoShift, injektTempoRamp
        case injektTempoBlend, injektBars, injektSkipIntro, injektAutoQueue, injektAnalyseAhead, injektAnalyseOnWifiOnly
        case offlineConcurrency, offlineBitrate, offlineWifiOnly, offlineFirst, streamCacheMb
        case autoSyncOnStart, autoSyncMinutes, syncPlaylistContents
        case showLyrics, homeTiles, favouriteRadios, hasSeenWelcome
    }

    /** Missing or unreadable values fall back to their defaults, one by one. */
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        func int(_ key: CodingKeys, _ fallback: Int) -> Int {
            c.int(key) ?? fallback
        }
        func double(_ key: CodingKeys, _ fallback: Double) -> Double {
            c.double(key) ?? fallback
        }
        theme = v(.theme, d.theme)
        accentMode = v(.accentMode, d.accentMode)
        accent = v(.accent, d.accent)
        accentBlend = int(.accentBlend, d.accentBlend)
        surfaceBorder = v(.surfaceBorder, d.surfaceBorder)
        borderOpacity = int(.borderOpacity, d.borderOpacity)
        surfaceOpacity = int(.surfaceOpacity, d.surfaceOpacity)
        corners = v(.corners, d.corners)
        playhead = v(.playhead, d.playhead)
        timeRemaining = v(.timeRemaining, d.timeRemaining)
        reduceMotion = v(.reduceMotion, d.reduceMotion)
        backdropArtwork = v(.backdropArtwork, d.backdropArtwork)
        gridSize = v(.gridSize, d.gridSize)
        compactRows = v(.compactRows, d.compactRows)
        crossfadeEnabled = v(.crossfadeEnabled, d.crossfadeEnabled)
        crossfadeSeconds = double(.crossfadeSeconds, d.crossfadeSeconds)
        crossfadeCurve = v(.crossfadeCurve, d.crossfadeCurve)
        crossfadeOnSkip = v(.crossfadeOnSkip, d.crossfadeOnSkip)
        gapless = v(.gapless, d.gapless)
        replayGainMode = v(.replayGainMode, d.replayGainMode)
        replayGainPreamp = double(.replayGainPreamp, d.replayGainPreamp)
        preferredBitrate = int(.preferredBitrate, d.preferredBitrate)
        preferredBitrateMobile = int(.preferredBitrateMobile, d.preferredBitrateMobile)
        preferredFormat = v(.preferredFormat, d.preferredFormat)
        scrobble = v(.scrobble, d.scrobble)
        resumeOnStart = v(.resumeOnStart, d.resumeOnStart)
        eqEnabled = v(.eqEnabled, d.eqEnabled)
        eqPreset = v(.eqPreset, d.eqPreset)
        eqGains = v(.eqGains, d.eqGains)
        eqPreamp = double(.eqPreamp, d.eqPreamp)
        injektEnabled = v(.injektEnabled, d.injektEnabled)
        injektBeatMatch = v(.injektBeatMatch, d.injektBeatMatch)
        injektBassSwap = v(.injektBassSwap, d.injektBassSwap)
        injektHarmonic = v(.injektHarmonic, d.injektHarmonic)
        injektMaxTempoShift = double(.injektMaxTempoShift, d.injektMaxTempoShift)
        injektTempoRamp = v(.injektTempoRamp, d.injektTempoRamp)
        injektTempoBlend = double(.injektTempoBlend, d.injektTempoBlend)
        injektBars = int(.injektBars, d.injektBars)
        injektSkipIntro = v(.injektSkipIntro, d.injektSkipIntro)
        injektAutoQueue = v(.injektAutoQueue, d.injektAutoQueue)
        injektAnalyseAhead = v(.injektAnalyseAhead, d.injektAnalyseAhead)
        injektAnalyseOnWifiOnly = v(.injektAnalyseOnWifiOnly, d.injektAnalyseOnWifiOnly)
        offlineConcurrency = int(.offlineConcurrency, d.offlineConcurrency)
        offlineBitrate = int(.offlineBitrate, d.offlineBitrate)
        offlineWifiOnly = v(.offlineWifiOnly, d.offlineWifiOnly)
        offlineFirst = v(.offlineFirst, d.offlineFirst)
        streamCacheMb = int(.streamCacheMb, d.streamCacheMb)
        autoSyncOnStart = v(.autoSyncOnStart, d.autoSyncOnStart)
        autoSyncMinutes = int(.autoSyncMinutes, d.autoSyncMinutes)
        syncPlaylistContents = v(.syncPlaylistContents, d.syncPlaylistContents)
        showLyrics = v(.showLyrics, d.showLyrics)
        homeTiles = v(.homeTiles, d.homeTiles)
        favouriteRadios = v(.favouriteRadios, d.favouriteRadios)
        hasSeenWelcome = v(.hasSeenWelcome, d.hasSeenWelcome)
    }

    /** EQ gains, always exactly one per band. */
    var eqBandGains: [Double] {
        (0..<EQ_BANDS.count).map { $0 < eqGains.count ? eqGains[$0] : 0 }
    }

    func withEqPreset(_ name: String) -> Settings {
        var copy = self
        copy.eqPreset = name
        copy.eqGains = EQ_PRESETS[name] ?? EQ_PRESETS["Flat"]!
        return copy
    }

    func bitrateFor(metered: Bool) -> Int {
        metered && preferredBitrateMobile >= 0 ? preferredBitrateMobile : preferredBitrate
    }

    /** A copy with [change] applied, like Kotlin's `copy`. */
    func with(_ change: (inout Settings) -> Void) -> Settings {
        var copy = self
        change(&copy)
        return copy
    }
}

enum TileKind: Hashable {
    case songs, albums, artists, playlists, radios
}

/** A shelf the home page can show. */
struct HomeTile: Hashable, Identifiable {
    let id: String
    /** Heading on the home page. */
    let title: String
    /** One line in Settings, explaining what fills it. */
    let note: String
    let kind: TileKind
}

let HOME_TILES: [HomeTile] = [
    HomeTile(id: "recentlyPlayed", title: "Jump back in", note: "Tracks you played most recently.", kind: .songs),
    HomeTile(id: "mostPlayedSongs", title: "Played the most", note: "Your most-played tracks, by the play count on the server.", kind: .songs),
    HomeTile(id: "mostPlayedAlbums", title: "Albums you keep coming back to", note: "Albums with the highest play counts.", kind: .albums),
    HomeTile(id: "mostPlayedArtists", title: "Artists you play most", note: "Worked out by adding up the play counts of each artist’s tracks.", kind: .artists),
    HomeTile(id: "mostPlayedPlaylists", title: "Playlists on repeat", note: "Ranked by the play counts of the tracks inside them.", kind: .playlists),
    HomeTile(id: "randomSongs", title: "Something else", note: "A different handful of tracks every time you open the page.", kind: .songs),
    HomeTile(id: "randomAlbums", title: "Albums at random", note: "A different handful of albums every time.", kind: .albums),
    HomeTile(id: "randomArtists", title: "Artists at random", note: "A different handful of artists every time.", kind: .artists),
    HomeTile(id: "recentlyAdded", title: "Recently added", note: "The newest albums in your library.", kind: .albums),
    HomeTile(id: "favouriteSongs", title: "Favourites", note: "Tracks you have hearted.", kind: .songs),
    HomeTile(id: "favouriteAlbums", title: "Favourite albums", note: "Albums you have hearted.", kind: .albums),
    HomeTile(id: "favouriteArtists", title: "Favourite artists", note: "Artists you have hearted.", kind: .artists),
    HomeTile(id: "favouritePlaylists", title: "Favourite playlists", note: "Playlists you own, newest first.", kind: .playlists),
    HomeTile(id: "favouriteRadios", title: "Favourite stations", note: "Internet radio you have hearted on the Radio page.", kind: .radios),
    HomeTile(id: "radios", title: "Internet radio", note: "Every station configured on your server.", kind: .radios),
]

private let tilesById: [String: HomeTile] = Dictionary(uniqueKeysWithValues: HOME_TILES.map { ($0.id, $0) })

func homeTile(_ id: String) -> HomeTile? {
    tilesById[id]
}

/** The enabled tiles, in order, ignoring any id that no longer exists. */
func resolveHomeTiles(_ ids: [String]) -> [HomeTile] {
    var seen = Set<String>()
    return ids.compactMap { id in
        guard let tile = tilesById[id], seen.insert(id).inserted else { return nil }
        return tile
    }
}

/** Everything not currently switched on, in catalogue order. */
func availableHomeTiles(_ ids: [String]) -> [HomeTile] {
    let on = Set(ids)
    return HOME_TILES.filter { !on.contains($0.id) }
}
