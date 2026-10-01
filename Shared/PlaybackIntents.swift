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
