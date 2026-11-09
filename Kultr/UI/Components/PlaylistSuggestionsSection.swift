import SwiftUI

/**
 * The suggestions under one playlist: the songs showing, the song they are
 * like once one has been added, and whether new ones are on the way. The
 * rules are PlaylistSuggestions in KultrCore, the same as Kultr for Android
 * and the web.
 */
@MainActor
@Observable
final class PlaylistSuggestionModel {
    /** The suggestions showing; nil until the first ones arrive. */
    private(set) var songs: [Song]?
    /** The song the suggestions are like, once one has been added. */
    private(set) var basis: Song?
    private(set) var busy = false
    /** The suggestion being added right now. */
    var adding: String?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let karousel: KarouselMusic

    init(graph: AppGraph) {
        karousel = KarouselMusic(graph: graph)
    }

    func load(_ playlist: [Song], added: Song?, leaveOut: [Song] = []) {
        task?.cancel()
        busy = true
        task = Task { [weak self] in
            guard let self else { return }
            let picks = await self.karousel.suggest(playlist: playlist, added: added, leaveOut: leaveOut)
            guard !Task.isCancelled else { return }
            self.songs = picks
            self.basis = added
            self.busy = false
        }
    }

    /** Takes [song] off the list once it is in the playlist. */
    func remove(_ song: Song) {
        songs = songs?.filter { $0.id != song.id }
    }
}

/**
 * Suggested songs at the bottom of a playlist, as on Spotify. Each has a +
 * to add it; once one is added, the suggestions turn to songs like it.
 * Refresh offers different ones.
 */
struct PlaylistSuggestionsSection: View {
    @Environment(\.kultr) private var theme
    let model: PlaylistSuggestionModel
    let playlist: [Song]
    let onAdd: (Song) -> Void

    var body: some View {
        let c = theme.colors
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Recommended songs") {
                if model.busy && model.songs != nil {
                    ProgressView().controlSize(.small)
                }
            }
            Text(subtitle)
                .font(KFont.bodySmall)
                .foregroundStyle(c.ink3)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            if let songs = model.songs {
                if songs.isEmpty {
                    Text("Nothing to suggest yet. Add a few songs, or play some music, and suggestions follow.")
                        .font(KFont.bodyMedium)
                        .foregroundStyle(c.ink2)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                } else {
                    ForEach(songs) { song in
                        SuggestionRow(
                            song: song,
                            adding: model.adding == song.id,
                            enabled: model.adding == nil,
                            onAdd: { onAdd(song) },
                            onPlay: { AppGraph.shared.actions.play([song]) }
                        )
                        .transition(.opacity)
                    }
                }
                Pill("Refresh", icon: "arrow.clockwise", enabled: !model.busy) {
                    model.load(playlist, added: model.basis, leaveOut: model.songs ?? [])
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }
        }
        .padding(.top, 12)
        .animation(theme.ease, value: model.songs?.map { $0.id } ?? [])
    }

    private var subtitle: String {
        if let basis = model.basis { return "More like “\(basis.title)”" }
        return playlist.isEmpty ? "Based on what you play most" : "Based on the songs in this playlist"
    }
}

/** One suggestion: tap it to play it, or + to add it to the playlist. */
private struct SuggestionRow: View {
    @Environment(\.kultr) private var theme
    let song: Song
    let adding: Bool
    let enabled: Bool
    let onAdd: () -> Void
    let onPlay: () -> Void

    var body: some View {
        let c = theme.colors
        HStack(spacing: 0) {
            Artwork(coverId: song.artworkId, size: 46)
                .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(KFont.bodyLarge.weight(.medium))
                    .foregroundStyle(c.ink)
                    .lineLimit(1)
                let sub = [song.artist, song.album].compactMap { $0 }.joined(separator: " · ")
                if !sub.isEmpty {
                    Text(sub)
                        .font(KFont.bodySmall)
                        .foregroundStyle(c.ink3)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let duration = song.duration {
                Text(Format.time(Double(duration)))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(c.ink3)
            }
            Button(action: onAdd) {
                ZStack {
                    if adding {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 22))
                            .foregroundStyle(c.ink2)
                    }
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .accessibilityLabel("Add “\(song.title)” to this playlist")
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
    }
}
