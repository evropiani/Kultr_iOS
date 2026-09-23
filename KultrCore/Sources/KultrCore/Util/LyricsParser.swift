import Foundation

struct LyricLine: Hashable {
    /** Seconds from the start of the track, or nil when the lyrics are not synced. */
    let start: Double?
    let text: String
}

struct LyricsDoc: Hashable {
    let lines: [LyricLine]
    let synced: Bool

    /** Index of the line being sung at [seconds], or -1. */
    func activeIndex(_ seconds: Double) -> Int {
        guard synced else { return -1 }
        var found = -1
        for (i, line) in lines.enumerated() {
            guard let start = line.start else { continue }
            if start <= seconds + 0.15 { found = i } else { break }
        }
        return found
    }
}

/** Split text into lines the way Kotlin's `lines()` does: on \n, \r\n or \r. */
func splitLines(_ text: String) -> [String] {
    text.replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .components(separatedBy: "\n")
}

enum LyricsParser {
    private static let lrcTime = try! NSRegularExpression(pattern: "\\[(\\d{1,3}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]")

    /**
     * Prefer OpenSubsonic's structured lyrics (synced when available), and
     * fall back to the classic plain-text endpoint. Plain text that is really
     * an LRC file is parsed as synced lyrics.
     */
    static func choose(_ structured: [StructuredLyrics], plain: Lyrics?) -> LyricsDoc? {
        let best = structured.first(where: { $0.synced && !($0.line ?? []).isEmpty }) ?? structured.first
        if let best, let lines = best.line, !lines.isEmpty {
            let offset = Double(best.offset ?? 0) / 1000
            return LyricsDoc(
                lines: lines.map { line in
                    LyricLine(start: best.synced ? line.start.map { Double($0) / 1000 + offset } : nil, text: line.value)
                },
                synced: best.synced
            )
        }
        let text = (plain?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        return parseLrc(text) ?? LyricsDoc(lines: splitLines(text).map { LyricLine(start: nil, text: $0) }, synced: false)
    }

    /** Parse "[mm:ss.xx] text" lines; nil if the text has no timestamps. */
    static func parseLrc(_ text: String) -> LyricsDoc? {
        var out: [LyricLine] = []
        for raw in splitLines(text) {
            let ns = raw as NSString
            let stamps = lrcTime.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = stamps.last else { continue }
            let bodyStart = last.range.location + last.range.length
            let body = ns.substring(from: bodyStart).trimmingCharacters(in: .whitespaces)
            for stamp in stamps {
                let minutes = Int(ns.substring(with: stamp.range(at: 1))) ?? 0
                let seconds = Int(ns.substring(with: stamp.range(at: 2))) ?? 0
                var fraction = 0.0
                let fractionRange = stamp.range(at: 3)
                if fractionRange.location != NSNotFound {
                    fraction = Double("0." + ns.substring(with: fractionRange)) ?? 0
                }
                out.append(LyricLine(start: Double(minutes * 60 + seconds) + fraction, text: body))
            }
        }
        if out.isEmpty { return nil }
        let sorted = out.enumerated().sorted { lhs, rhs in
            let a = lhs.element.start ?? 0
            let b = rhs.element.start ?? 0
            return a != b ? a < b : lhs.offset < rhs.offset
        }.map { $0.element }
        return LyricsDoc(lines: sorted, synced: true)
    }
}
