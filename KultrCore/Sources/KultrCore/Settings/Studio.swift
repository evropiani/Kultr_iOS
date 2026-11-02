import Foundation

// ----------------------------------------------------------- Home widgets --

/** A widget on Home: what it shows, and how big it is. */
struct HomeWidget: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        case nowPlaying, listening, nextMix, station, crate, shortcut

        var label: String {
            switch self {
            case .nowPlaying: return "Now playing"
            case .listening: return "Listening this week"
            case .nextMix: return "Next mix"
            case .station: return "A station"
            case .crate: return "A crate"
            case .shortcut: return "A shortcut"
            }
        }

        var note: String {
            switch self {
            case .nowPlaying: return "The track, with play and skip. Tap to open the player."
            case .listening: return "Hours this week, against your usual."
            case .nextMix: return "What InjeKt plays next, and when."
            case .station: return "One tap starts it."
            case .crate: return "Its covers; tap to play it."
            case .shortcut: return "One tap for anything you'd type in Search."
            }
        }

        var icon: String {
            switch self {
            case .nowPlaying: return "play.circle.fill"
            case .listening: return "chart.bar.fill"
            case .nextMix: return "arrow.triangle.merge"
            case .station: return "dial.medium.fill"
            case .crate: return "shippingbox.fill"
            case .shortcut: return "bolt.fill"
            }
        }
    }

    enum Size: String, Codable, CaseIterable {
        case small, medium, large

        var label: String { rawValue.capitalized }
    }

    var id: String
    var kind: Kind
    var size: Size
    /** The station's or crate's id, or the shortcut's words ("sleep in 30 minutes"). */
    var ref: String?

    init(id: String = UUID().uuidString, kind: Kind, size: Size, ref: String? = nil) {
        self.id = id
        self.kind = kind
        self.size = size
        self.ref = ref
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .nowPlaying
        size = (try? c.decode(Size.self, forKey: .size)) ?? .small
        ref = try? c.decodeIfPresent(String.self, forKey: .ref)
    }
}

let DEFAULT_HOME_WIDGETS: [HomeWidget] = [
    HomeWidget(id: "now", kind: .nowPlaying, size: .medium),
    HomeWidget(id: "listening", kind: .listening, size: .small),
    HomeWidget(id: "next", kind: .nextMix, size: .small),
]

/**
 * Widgets in rows of a two-column grid: small ones side by side, medium and
 * large ones across the whole width. Returns rows of widget indices.
 */
func homeWidgetRows(_ widgets: [HomeWidget]) -> [[Int]] {
    var rows: [[Int]] = []
    var pending: Int?
    for (i, widget) in widgets.enumerated() {
        if widget.size == .small {
            if let first = pending {
                rows.append([first, i])
                pending = nil
            } else {
                pending = i
            }
        } else {
            if let first = pending {
                rows.append([first])
                pending = nil
            }
            rows.append([i])
        }
    }
    if let first = pending { rows.append([first]) }
    return rows
}

// ---------------------------------------------------------- Kultr Studio --

/** The player's parts, in the order they can be stacked. */
enum PlayerBlock: String, Codable, CaseIterable, Hashable {
    case artwork, title, facts, progress, transport

    var label: String {
        switch self {
        case .artwork: return "Cover"
        case .title: return "Title and artist"
        case .facts: return "Info line"
        case .progress: return "Progress"
        case .transport: return "Buttons"
        }
    }
}

/**
 * A text template with conditions, for the player's info line:
 * "{year}{?genre: · {genre}}" shows the genre, and its dot, only when the
 * track has one. Unknown names come out empty.
 */
func renderTemplate(_ template: String, _ values: [String: String]) -> String {
    var out = ""
    var i = template.startIndex
    while i < template.endIndex {
        let ch = template[i]
        guard ch == "{" else {
            out.append(ch)
            i = template.index(after: i)
            continue
        }
        // Find the matching close brace, allowing nested ones.
        var depth = 0
        var j = i
        while j < template.endIndex {
            if template[j] == "{" { depth += 1 }
            if template[j] == "}" {
                depth -= 1
                if depth == 0 { break }
            }
            j = template.index(after: j)
        }
        guard j < template.endIndex else {
            out += template[i...]
            break
        }
        let inner = String(template[template.index(after: i)..<j])
        if inner.hasPrefix("?"), let colon = inner.firstIndex(of: ":") {
            let key = String(inner[inner.index(after: inner.startIndex)..<colon]).trimmingCharacters(in: .whitespaces)
            if !(values[key] ?? "").isEmpty {
                out += renderTemplate(String(inner[inner.index(after: colon)...]), values)
            }
        } else {
            out += values[inner.trimmingCharacters(in: .whitespaces)] ?? ""
        }
        i = template.index(after: j)
    }
    return out
}

/** The names a template can use, with an example of each. */
let TEMPLATE_FIELDS: [(name: String, example: String)] = [
    ("year", "2019"), ("genre", "Electronic"), ("format", "FLAC"), ("bitrate", "1024"), ("bpm", "124"),
    ("key", "8A"), ("energy", "7"), ("rating", "4"), ("plays", "12"), ("album", "Night Ferries"),
]

/**
 * A look for the whole app, as Kultr Studio edits and shares it: the colours,
 * the shape, the glass and how the player is put together. Plain JSON, so it
 * travels as a small file or a link.
 */
struct StudioStyle: Codable, Hashable {
    var name: String
    var theme: ThemeMode
    var nightMode: Bool
    var accentMode: AccentMode
    var accent: String
    var corners: CornerStyle
    var gridSize: GridSize
    var compactRows: Bool
    var playhead: PlayheadStyle
    var backdropArtwork: Bool
    var clearGlass: Bool
    var playerBlocks: [PlayerBlock]
    /** Empty for Kultr's own info line, with the genre and rating to tap. */
    var factsTemplate: String

    init(settings: Settings, name: String = "My style") {
        self.name = name
        theme = settings.theme
        nightMode = settings.nightMode
        accentMode = settings.accentMode
        accent = settings.accent
        corners = settings.corners
        gridSize = settings.gridSize
        compactRows = settings.compactRows
        playhead = settings.playhead
        backdropArtwork = settings.backdropArtwork
        clearGlass = settings.clearGlass
        playerBlocks = settings.playerBlocks
        factsTemplate = settings.factsTemplate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StudioStyle(settings: Settings())
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        name = v(.name, "Shared style")
        theme = v(.theme, d.theme)
        nightMode = v(.nightMode, d.nightMode)
        accentMode = v(.accentMode, d.accentMode)
        accent = v(.accent, d.accent)
        corners = v(.corners, d.corners)
        gridSize = v(.gridSize, d.gridSize)
        compactRows = v(.compactRows, d.compactRows)
        playhead = v(.playhead, d.playhead)
        backdropArtwork = v(.backdropArtwork, d.backdropArtwork)
        clearGlass = v(.clearGlass, d.clearGlass)
        let blocks = v(.playerBlocks, d.playerBlocks)
        playerBlocks = blocks.isEmpty ? d.playerBlocks : blocks
        factsTemplate = v(.factsTemplate, d.factsTemplate)
    }

    /** [settings] with this look; everything that isn't the look stays. */
    func applied(to settings: Settings) -> Settings {
        settings.with { s in
            s.theme = theme
            s.nightMode = nightMode
            s.accentMode = accentMode
            if accent.hasPrefix("#") && accent.count == 7 { s.accent = accent }
            s.corners = corners
            s.gridSize = gridSize
            s.compactRows = compactRows
            s.playhead = playhead
            s.backdropArtwork = backdropArtwork
            s.clearGlass = clearGlass
            s.playerBlocks = playerBlocks
            s.factsTemplate = factsTemplate
        }
    }

    /** Whether [settings] look like this already. */
    func matches(_ settings: Settings) -> Bool {
        var mine = self
        mine.name = ""
        var theirs = StudioStyle(settings: settings)
        theirs.name = ""
        return mine == theirs
    }

    // ---------------------------------------------------------- sharing --

    static let linkPrefix = "kultr://style/"

    /** The style as a link, like kultr://style/eyJuYW1l… */
    var link: String {
        guard let data = try? JSONEncoder().encode(self) else { return Self.linkPrefix }
        let base64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return Self.linkPrefix + base64
    }

    /** A style from a link, or from a style file's text. */
    static func read(_ text: String) -> StudioStyle? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") {
            return try? JSONDecoder().decode(StudioStyle.self, from: Data(trimmed.utf8))
        }
        guard let range = trimmed.range(of: "style/") else { return nil }
        var base64 = String(trimmed[range.upperBound...])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONDecoder().decode(StudioStyle.self, from: data)
    }
}

/** Styles Kultr comes with. */
let STUDIO_PRESETS: [StudioStyle] = {
    let base = StudioStyle(settings: Settings(), name: "Cream")
    var night = base
    night.name = "Night"
    night.theme = .dark
    night.nightMode = true
    var ember = base
    ember.name = "Ember"
    ember.theme = .dark
    ember.accentMode = .artwork
    ember.backdropArtwork = true
    ember.playhead = .glow
    ember.corners = .round
    var paper = base
    paper.name = "Paper"
    paper.theme = .light
    paper.corners = .sharp
    paper.compactRows = true
    paper.gridSize = .small
    paper.clearGlass = true
    var console = base
    console.name = "Console"
    console.theme = .dark
    console.corners = .sharp
    console.compactRows = true
    console.playhead = .equalizer
    console.factsTemplate = "{?bpm:{bpm} BPM}{?key: · {key}}{?energy: · energy {energy}}{?format: · {format}}"
    console.playerBlocks = [.title, .progress, .transport, .facts, .artwork]
    return [base, night, ember, paper, console]
}()
