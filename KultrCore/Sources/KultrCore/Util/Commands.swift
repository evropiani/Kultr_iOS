import Foundation

/** Places the command bar can open. */
enum CommandPlace: String, CaseIterable, Hashable {
    case home, library, settings, listening, recap, stations, crates, downloads, planner, search
}

/** Something typed into the command bar that Kultr can do, rather than look for. */
enum KultrCommand: Hashable {
    case play(String)
    case shuffle(String)
    case shuffleAll
    case station(String)
    case sleep(minutes: Int)
    case sleepAfterTrack
    case pause, resume, next, previous, mixNow
    case plan(minutes: Int?)
    case open(CommandPlace)
    case crate(String)
    case playCrate(String)
}

/**
 * Reads plain words as a command: "play night drive", "shuffle radiohead",
 * "sleep in 30 minutes", "next", "open settings", "plan an hour". [stations]
 * and [crates] are their names, so "play night drive" can start the station
 * rather than search for a song. Nil when the words aren't a command.
 */
func parseCommand(_ text: String, stations: [String] = [], crates: [String] = []) -> KultrCommand? {
    let words = text.lowercased()
        .replacingOccurrences(of: "[^\\p{L}\\p{N}' ]", with: " ", options: .regularExpression)
        .split(separator: " ")
        .map(String.init)
    guard !words.isEmpty else { return nil }
    let line = words.joined(separator: " ")
    func rest(after count: Int) -> String { words.dropFirst(count).joined(separator: " ") }
    func named(_ name: String, in names: [String]) -> String? {
        let wanted = name.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return nil }
        return names.first { $0.lowercased() == wanted } ?? names.first { $0.lowercased().hasPrefix(wanted) && wanted.count >= 3 }
    }

    switch line {
    case "pause", "stop", "stop the music", "be quiet": return .pause
    case "play", "resume", "continue", "go on", "unpause": return .resume
    case "next", "skip", "next track", "next song", "skip this": return .next
    case "previous", "back", "go back", "previous track", "previous song", "last song": return .previous
    case "mix", "mix now", "mix it", "blend", "mix into the next one": return .mixNow
    case "shuffle", "shuffle all", "shuffle everything", "shuffle my library", "surprise me": return .shuffleAll
    case "sleep after this", "sleep after this song", "sleep after this track", "stop after this song", "stop after this track":
        return .sleepAfterTrack
    default: break
    }

    // Sleep in 30 minutes, stop in an hour, timer 45.
    if ["sleep", "timer", "stop"].contains(words[0]) || line.hasPrefix("sleep timer") {
        if let minutes = minutesIn(Array(words.dropFirst())) { return .sleep(minutes: minutes) }
    }
    // Plan a set, plan an hour, plan 90 minutes.
    if words[0] == "plan" || line.hasPrefix("build a set") || line.hasPrefix("make a set") {
        return .plan(minutes: minutesIn(Array(words.dropFirst())))
    }
    // Open settings, show my stations, go to listening.
    if ["open", "show", "go"].contains(words[0]) {
        var target = Array(words.dropFirst())
        if target.first == "to" { target.removeFirst() }
        if ["my", "the"].contains(target.first ?? "") { target.removeFirst() }
        let place = target.joined(separator: " ")
        let aliases: [String: CommandPlace] = [
            "home": .home, "library": .library, "settings": .settings, "preferences": .settings,
            "listening": .listening, "stats": .listening, "statistics": .listening, "history": .listening,
            "recap": .recap, "monthly recap": .recap, "month": .recap, "stations": .stations, "dial": .stations,
            "crates": .crates, "downloads": .downloads, "planner": .planner, "energy planner": .planner, "search": .search,
        ]
        if let match = aliases[place] { return .open(match) }
        if target.first == "crate", let crate = named(target.dropFirst().joined(separator: " "), in: crates) { return .crate(crate) }
        if let crate = named(place, in: crates) { return .crate(crate) }
    }
    if words[0] == "crate", let crate = named(rest(after: 1), in: crates) { return .crate(crate) }
    // Station night drive, tune in to warm up, play the station peak hour.
    if words[0] == "station" { return named(rest(after: 1), in: stations).map(KultrCommand.station) ?? .station(rest(after: 1)) }
    if words.count > 2, words[0] == "tune", ["in", "to"].contains(words[1]) {
        let name = words[1] == "in" && words.count > 3 && words[2] == "to" ? rest(after: 3) : rest(after: 2)
        return .station(named(name, in: stations) ?? name)
    }
    if line.hasPrefix("play the station ") { return .station(named(rest(after: 3), in: stations) ?? rest(after: 3)) }
    if words[0] == "shuffle", words.count > 1 { return .shuffle(rest(after: 1)) }
    if words[0] == "play", words.count > 1 {
        let what = rest(after: 1)
        if let station = named(what, in: stations) { return .station(station) }
        if let crate = named(what, in: crates) { return .playCrate(crate) }
        return .play(what.hasPrefix("some ") ? String(what.dropFirst(5)) : what)
    }
    return nil
}

/** "30", "30 minutes", "half an hour", "an hour", "2 hours", "1h", "90min". */
private func minutesIn(_ words: [String]) -> Int? {
    var words = words
    if ["in", "for", "after"].contains(words.first ?? "") { words.removeFirst() }
    let line = words.joined(separator: " ")
    if line.hasPrefix("half an hour") || line.hasPrefix("half hour") { return 30 }
    if line.hasPrefix("an hour and a half") || line.hasPrefix("one and a half hours") { return 90 }
    if line.hasPrefix("an hour") || line.hasPrefix("one hour") || line == "hour" { return 60 }
    let numbers: [String: Int] = ["one": 1, "two": 2, "three": 3, "five": 5, "ten": 10, "fifteen": 15, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "ninety": 90]
    guard let first = words.first else { return nil }
    let digits = first.prefix { $0.isNumber }
    let unitInline = first.dropFirst(digits.count)
    guard let value = Int(digits) ?? numbers[first] else { return nil }
    let unit = !unitInline.isEmpty ? String(unitInline) : (words.count > 1 ? words[1] : "min")
    let hours = unit.hasPrefix("h")
    let minutes = hours ? value * 60 : value
    return (1...24 * 60).contains(minutes) ? minutes : nil
}
