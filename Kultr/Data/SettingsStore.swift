import Foundation
import Observation

/**
 * Every preference, as one JSON document in UserDefaults. Reads are
 * synchronous (the player needs them without suspending), and every change
 * is published through [settings] and to registered listeners.
 */
@MainActor
@Observable
final class SettingsStore {
    private static let key = "settings.json"

    private(set) var settings: Settings

    @ObservationIgnored private var listeners: [(Settings, Settings) -> Void] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = decoded
        } else {
            settings = Settings()
        }
        moveToCream()
        addShelf("rediscover", after: "mostPlayedAlbums")
    }

    /** A new home shelf, once, so it shows up without a trip to Settings. Removing it afterwards sticks. */
    private func addShelf(_ id: String, after: String) {
        let key = "home.added.\(id)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        update { s in
            guard !s.homeTiles.contains(id) else { return }
            if let at = s.homeTiles.firstIndex(of: after) {
                s.homeTiles.insert(id, at: at + 1)
            } else {
                s.homeTiles.append(id)
            }
        }
    }

    /**
     * 1.4.0's look, once: the old defaults (periwinkle taken from the artwork,
     * blurred covers behind every page, accent-tinted borders) become the new
     * ones. A colour someone picked themselves is kept; everything here can be
     * switched back in Settings > Appearance.
     */
    private func moveToCream() {
        let key = "look.cream"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let fresh = Settings()
        update { s in
            if s.accent.lowercased() == "#7c8cff" { s.accent = fresh.accent }
            s.accentMode = fresh.accentMode
            s.backdropArtwork = fresh.backdropArtwork
            s.surfaceBorder = fresh.surfaceBorder
        }
    }

    var current: Settings { settings }

    /** Called with (old, new) after every change. */
    func observe(_ listener: @escaping (Settings, Settings) -> Void) {
        listeners.append(listener)
    }

    func update(_ change: (inout Settings) -> Void) {
        let old = settings
        var next = old
        change(&next)
        if next == old { return }
        settings = next
        if let data = try? JSONEncoder().encode(next) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
        for listener in listeners { listener(old, next) }
    }

    func replace(_ settings: Settings) {
        update { $0 = settings }
    }

    func reset() {
        let seen = settings.hasSeenWelcome
        update { s in
            s = Settings()
            s.hasSeenWelcome = seen
        }
    }
}
