import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/**
 * The command bar: words typed into Search that Kultr can do rather than look
 * for. The rules in parseCommand() read the usual phrasings on every iPhone;
 * where Apple Intelligence is on, the on-device model reads the rest, and
 * nothing leaves the phone either way.
 */
@MainActor
enum CommandRunner {
    static var stationNames: [String] { AppGraph.shared.stations.all.map(\.name) }
    static var crateNames: [String] { AppGraph.shared.crates.all.map(\.name) }

    static func parse(_ text: String) -> KultrCommand? {
        parseCommand(text, stations: stationNames, crates: crateNames)
    }

    /** What the command will do, for the row above the search results. */
    static func describe(_ command: KultrCommand) -> (icon: String, text: String) {
        switch command {
        case .play(let what): return ("play.fill", "Play “\(what)”")
        case .shuffle(let what): return ("shuffle", "Shuffle “\(what)”")
        case .shuffleAll: return ("shuffle", "Shuffle your whole library")
        case .station(let name): return ("dial.medium.fill", "Play the station \(name)")
        case .sleep(let minutes): return ("moon.fill", "Sleep timer: \(minutes) min")
        case .sleepAfterTrack: return ("moon.fill", "Stop after this track")
        case .pause: return ("pause.fill", "Pause")
        case .resume: return ("play.fill", "Play")
        case .next: return ("forward.end.fill", "Next track")
        case .previous: return ("backward.end.fill", "Previous track")
        case .mixNow: return ("arrow.triangle.merge", "Mix into the next track")
        case .plan(let minutes): return ("waveform.path.ecg", minutes.map { "Plan a set of \($0) min" } ?? "Plan a set")
        case .open(let place): return ("arrow.up.forward.app", "Open \(label(place))")
        case .crate(let name): return ("shippingbox.fill", "Open the crate \(name)")
        case .playCrate(let name): return ("shippingbox.fill", "Play the crate \(name)")
        }
    }

    private static func label(_ place: CommandPlace) -> String {
        switch place {
        case .home: return "Home"
        case .library: return "Library"
        case .settings: return "Settings"
        case .listening: return "Listening"
        case .recap: return "the monthly recap"
        case .stations: return "Stations"
        case .crates: return "Crates"
        case .downloads: return "Downloads"
        case .planner: return "the energy planner"
        case .search: return "Search"
        }
    }

    static func run(_ command: KultrCommand) async {
        let graph = AppGraph.shared
        let player = graph.player
        let actions = graph.actions
        switch command {
        case .play(let what), .shuffle(let what):
            let songs = await music(for: what)
            guard !songs.isEmpty else {
                graph.messages.show("Nothing in your library matches “\(what)”.")
                return
            }
            if case .shuffle = command { actions.shuffle(songs) } else { actions.play(songs) }
        case .shuffleAll:
            actions.shuffle(await graph.library.randomSongs(200))
        case .station(let name):
            guard let station = graph.stations.all.first(where: { $0.name.lowercased() == name.lowercased() }) else {
                graph.messages.show("There's no station called “\(name)”. Stations has the list.")
                return
            }
            await player.playStation(station)
        case .sleep(let minutes):
            player.setSleepTimer(minutes: minutes)
            graph.messages.show("Sleep timer: \(minutes) minutes.")
        case .sleepAfterTrack:
            player.sleepAtEndOfTrack()
            graph.messages.show("Stopping after this track.")
        case .pause: player.pause()
        case .resume: player.resume()
        case .next: player.next()
        case .previous: player.previous()
        case .mixNow:
            if !player.mixNow() { graph.messages.show("Nothing to mix into: this is the last track") }
        case .plan(let minutes): actions.navigate(.planner(minutes))
        case .open(let place):
            switch place {
            case .home: actions.selectTab(.home)
            case .library: actions.selectTab(.library)
            case .settings: actions.selectTab(.settings)
            case .search: actions.selectTab(.search)
            case .listening: actions.navigate(.stats)
            case .recap: actions.navigate(.recap)
            case .stations: actions.navigate(.stations)
            case .crates: actions.openLibrary(.crates)
            case .downloads: actions.openDownloads()
            case .planner: actions.navigate(.planner(nil))
            }
        case .crate(let name):
            if let crate = graph.crates.all.first(where: { $0.name.lowercased() == name.lowercased() }) { actions.openCrate(crate.id) }
        case .playCrate(let name):
            guard let crate = graph.crates.all.first(where: { $0.name.lowercased() == name.lowercased() }) else { return }
            let songs = await graph.crates.songs(crate)
            if songs.isEmpty { graph.messages.show("“\(crate.name)” is empty.") } else { actions.play(songs) }
        }
    }

    /** The music [what] names: an artist, then an album, then tracks, as the library search finds them. */
    private static func music(for what: String) async -> [Song] {
        let graph = AppGraph.shared
        let found = await graph.library.search(what)
        let wanted = what.lowercased()
        if let artist = found.artists.first(where: { $0.name.lowercased() == wanted }) ?? (found.albums.isEmpty && found.songs.isEmpty ? found.artists.first : nil) {
            return await graph.actions.artistSongs(artist)
        }
        if let album = found.albums.first(where: { $0.name.lowercased() == wanted }) ?? (found.songs.isEmpty ? found.albums.first : nil) {
            return await graph.library.songsOfAlbumNow(album.id)
        }
        if let artist = found.artists.first { return await graph.actions.artistSongs(artist) }
        return found.songs
    }

    // ------------------------------------------------- Apple Intelligence --

    /** Whether the on-device model can read what the rules couldn't. */
    static var canInterpret: Bool {
        #if canImport(FoundationModels)
        return SystemLanguageModel.default.isAvailable
        #else
        return false
        #endif
    }

    /** Plain words the rules didn't understand, read by the on-device model into a command, or nil. */
    static func interpret(_ text: String) async -> KultrCommand? {
        #if canImport(FoundationModels)
        guard SystemLanguageModel.default.isAvailable else { return nil }
        let stations = stationNames
        let crates = crateNames
        let session = LanguageModelSession(instructions: """
        You turn one request to a music player into one action. Actions: play, shuffle, station, sleep, pause, \
        resume, next, previous, mix, plan, open, crate, none. "station" plays one of these stations: \
        \(stations.joined(separator: ", ")). "crate" plays one of these crates: \(crates.joined(separator: ", ")). \
        "open" goes to one of: home, library, settings, listening, recap, stations, crates, downloads, planner. \
        "sleep" sets a sleep timer and "plan" builds a set, both for some minutes. Use "none" for anything else.
        """)
        guard let guess = try? await session.respond(to: text, generating: CommandGuess.self).content else { return nil }
        let subject = guess.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let words: String
        switch guess.action.lowercased() {
        case "none": return nil
        case "sleep": words = guess.minutes > 0 ? "sleep \(guess.minutes)" : ""
        case "plan": words = guess.minutes > 0 ? "plan \(guess.minutes) minutes" : "plan a set"
        case "mix": words = "mix now"
        case "crate": words = "play \(subject)"
        default: words = "\(guess.action) \(subject)"
        }
        return parseCommand(words, stations: stations, crates: crates)
        #else
        return nil
        #endif
    }
}

#if canImport(FoundationModels)
@Generable
struct CommandGuess {
    @Guide(description: "One of: play, shuffle, station, sleep, pause, resume, next, previous, mix, plan, open, crate, none")
    var action: String
    @Guide(description: "What to play, the station or crate's name, or the place to open; empty when there is none")
    var subject: String
    @Guide(description: "Minutes for a sleep timer or a planned set; 0 when there are none")
    var minutes: Int
}
#endif
