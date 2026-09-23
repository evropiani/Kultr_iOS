import Foundation

/** Formatting helpers shared across the UI. */
enum Format {
    /** "3:07", or "1:02:03" past an hour. */
    static func time(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(min(seconds, 1e12).rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%ld:%02ld:%02ld", hours, minutes, secs)
        }
        return String(format: "%ld:%02ld", minutes, secs)
    }

    static func timeMs(_ ms: Int64?) -> String {
        time(ms.map { Double($0) / 1000 })
    }

    /** "1 hr 24 min" style duration, for albums and playlists. */
    static func duration(_ seconds: Int64?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        let hours = seconds / 3600
        let minutes = Int((Double(seconds % 3600) / 60).rounded())
        if hours > 0 { return "\(hours) hr \(minutes) min" }
        if minutes > 0 { return "\(minutes) min" }
        return "\(seconds) sec"
    }

    static func bytes(_ bytes: Int64?) -> String {
        guard let bytes, bytes > 0 else { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        let exponent = min(units.count - 1, Int(floor(log(Double(bytes)) / log(1024.0))))
        let value = Double(bytes) / pow(1024.0, Double(exponent))
        let digits = value >= 10 || exponent == 0 ? 0 : 1
        return String(format: "%.\(digits)f %@", value, units[exponent])
    }

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    static func count(_ value: Int?, _ singular: String, _ plural: String? = nil) -> String {
        let n = value ?? 0
        let text = integerFormatter.string(from: NSNumber(value: n)) ?? String(n)
        return "\(text) \(n == 1 ? singular : (plural ?? singular + "s"))"
    }

    static func number(_ value: Int) -> String {
        integerFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func relative(_ timestamp: Int64?, now: Int64 = Format.nowMs()) -> String {
        guard let timestamp, timestamp > 0 else { return "never" }
        let minutes = Int64((Double(now - timestamp) / 60_000).rounded())
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = Int64((Double(minutes) / 60).rounded())
        if hours < 24 { return "\(hours) hr ago" }
        let days = Int64((Double(hours) / 24).rounded())
        if days < 30 { return "\(days) day\(days == 1 ? "" : "s") ago" }
        return dateFormatter.string(from: Date(timeIntervalSince1970: Double(timestamp) / 1000))
    }

    private static let articles = try! NSRegularExpression(
        pattern: "^(the|a|an|der|die|das|le|la|les|el|los)\\s+",
        options: [.caseInsensitive]
    )

    /** "The Beatles" sorts under B, like every other music app. */
    static func sortKey(_ name: String?) -> String {
        guard let name else { return "" }
        let range = NSRange(name.startIndex..., in: name)
        return articles.stringByReplacingMatches(in: name, range: range, withTemplate: "").lowercased()
    }

    static func initials(_ name: String?) -> String {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "?" }
        let words = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(2)
        let letters = words.compactMap { $0.first?.uppercased() }.joined()
        return letters.isEmpty ? "?" : letters
    }

    static func greeting(_ hour: Int) -> String {
        if hour < 5 { return "Still up?" }
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }
}
