import AppIntents

// The widget's buttons. Audio playback intents run in the app's process (the
// system starts Kultr in the background if it has to), so the widget only
// names them; the app target does the work.

struct TogglePlaybackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play or pause"
    static let description = IntentDescription("Plays or pauses Kultr.")

    func perform() async throws -> some IntentResult {
        #if !KULTR_WIDGET
        await MainActor.run { KultrIntentActions.toggle() }
        #endif
        return .result()
    }
}

struct NextTrackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Next track"
    static let description = IntentDescription("Skips to the next track in Kultr.")

    func perform() async throws -> some IntentResult {
        #if !KULTR_WIDGET
        await MainActor.run { KultrIntentActions.next() }
        #endif
        return .result()
    }
}

struct PreviousTrackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Previous track"
    static let description = IntentDescription("Goes back to the previous track in Kultr.")

    func perform() async throws -> some IntentResult {
        #if !KULTR_WIDGET
        await MainActor.run { KultrIntentActions.previous() }
        #endif
        return .result()
    }
}

struct ToggleShuffleIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Shuffle on or off"
    static let description = IntentDescription("Turns shuffle on or off in Kultr.")

    func perform() async throws -> some IntentResult {
        #if !KULTR_WIDGET
        await MainActor.run { KultrIntentActions.toggleShuffle() }
        #endif
        return .result()
    }
}

struct CycleRepeatIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Repeat"
    static let description = IntentDescription("Switches Kultr between no repeat, repeating the queue and repeating the song.")

    func perform() async throws -> some IntentResult {
        #if !KULTR_WIDGET
        await MainActor.run { KultrIntentActions.cycleRepeat() }
        #endif
        return .result()
    }
}

/** A song under "Up next" in the large widgets, tapped: play it now. */
struct PlayQueuedSongIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play from the queue"
    static let description = IntentDescription("Plays a song that is waiting in Kultr's queue.")
    static let isDiscoverable = false

    @Parameter(title: "Place in the queue")
    var index: Int

    @Parameter(title: "Song")
    var songId: String

    init() {}

    init(index: Int, songId: String) {
        self.index = index
        self.songId = songId
    }

    func perform() async throws -> some IntentResult {
        #if !KULTR_WIDGET
        let index = index
        let songId = songId
        await MainActor.run { KultrIntentActions.playQueued(index: index, songId: songId) }
        #endif
        return .result()
    }
}
