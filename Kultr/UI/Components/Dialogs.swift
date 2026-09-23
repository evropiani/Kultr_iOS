import SwiftUI

/** A sheet body in Kultr's style: a title, the content, and a row of text buttons. */
struct SheetScaffold<Content: View, Buttons: View>: View {
    @Environment(\.kultr) private var theme
    let title: String
    @ViewBuilder var content: Content
    @ViewBuilder var buttons: Buttons

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(KFont.headlineSmall.weight(.semibold))
                .foregroundStyle(theme.colors.ink)
                .lineLimit(2)
            content
            HStack(spacing: 16) {
                Spacer()
                buttons
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.elevated.ignoresSafeArea())
        .tint(theme.colors.accent)
    }
}

struct TextButton: View {
    @Environment(\.kultr) private var theme
    let text: String
    var color: Color?
    var enabled = true
    let action: () -> Void

    init(_ text: String, color: Color? = nil, enabled: Bool = true, action: @escaping () -> Void) {
        self.text = text
        self.color = color
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(KFont.labelLarge)
                .foregroundStyle((color ?? theme.colors.accent).opacity(enabled ? 1 : 0.4))
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
    }
}

struct AddToPlaylistSheet: View {
    @Environment(\.kultr) private var theme
    let songs: [Song]
    let onDismiss: () -> Void
    @State private var playlists: [Playlist] = []
    @State private var name = ""
    @State private var busy = false

    private var label: String {
        songs.count == 1 ? "“\(songs[0].title)”" : "\(songs.count) tracks"
    }

    var body: some View {
        let library = AppGraph.shared.library
        SheetScaffold(title: "Add \(label) to…") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("New playlist", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                    IconButton(icon: "plus", tint: theme.colors.accent, label: "Create playlist") { create() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(playlists) { playlist in
                            Button {
                                add(to: playlist)
                            } label: {
                                HStack(spacing: 12) {
                                    Artwork(coverId: playlist.coverArt, size: 40, label: playlist.name)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(playlist.name).font(KFont.bodyLarge).foregroundStyle(theme.colors.ink)
                                        Text(Format.count(playlist.songCount, "track")).font(KFont.bodySmall).foregroundStyle(theme.colors.ink3)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableStyle())
                            .disabled(busy)
                        }
                    }
                }
                .frame(maxHeight: 360)
                if playlists.isEmpty {
                    Text("No playlists yet — name one above to create it.").foregroundStyle(theme.colors.ink3)
                }
            }
        } buttons: {
            TextButton("Cancel", action: onDismiss)
        }
        .task(id: library.version) { playlists = await library.playlists() }
    }

    private func finish(_ error: String?, _ success: String) {
        busy = false
        if let error {
            AppGraph.shared.messages.error(error)
        } else {
            AppGraph.shared.messages.success(success)
            onDismiss()
        }
    }

    private func create() {
        busy = true
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        Task { finish(await AppGraph.shared.library.createPlaylist(trimmed, songs), "Created “\(trimmed)”") }
    }

    private func add(to playlist: Playlist) {
        busy = true
        Task { finish(await AppGraph.shared.library.addToPlaylist(playlist.id, songs), "Added \(label) to “\(playlist.name)”") }
    }
}

struct RatingSheet: View {
    @Environment(\.kultr) private var theme
    let song: Song
    let onDismiss: () -> Void
    @State private var rating = 0

    var body: some View {
        SheetScaffold(title: "Rate “\(song.title)”") {
            HStack(spacing: 4) {
                Spacer()
                ForEach(1...5, id: \.self) { star in
                    Button {
                        rating = rating == star ? 0 : star
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.system(size: 30))
                            .foregroundStyle(star <= rating ? theme.colors.accent : theme.colors.ink3)
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("\(star) stars")
                }
                Spacer()
            }
        } buttons: {
            TextButton("Cancel", color: theme.colors.ink2, action: onDismiss)
            TextButton("Save") {
                AppGraph.shared.actions.setRating(song, rating)
                onDismiss()
            }
        }
        .onAppear { rating = song.userRating ?? 0 }
    }
}

struct SleepTimerSheet: View {
    @Environment(\.kultr) private var theme
    let onDismiss: () -> Void

    var body: some View {
        let player = AppGraph.shared.player
        let messages = AppGraph.shared.messages
        SheetScaffold(title: "Sleep timer") {
            VStack(alignment: .leading, spacing: 0) {
                if let timer = player.sleepTimer {
                    Group {
                        if timer.endOfTrack {
                            Text("Stopping at the end of this track.")
                        } else if let ends = timer.endsAt {
                            Text("Stopping in \(max(0, Int(ends.timeIntervalSinceNow / 60)) + 1) min.")
                        }
                    }
                    .foregroundStyle(theme.colors.accent)
                    .padding(.bottom, 8)
                }
                ForEach([5, 15, 30, 45, 60, 90], id: \.self) { minutes in
                    option("\(minutes) minutes") {
                        player.setSleepTimer(minutes: minutes)
                        messages.show("Sleep timer: \(minutes) minutes.")
                    }
                }
                option("At the end of this track") {
                    player.sleepAtEndOfTrack()
                    messages.show("Stopping after this track.")
                }
            }
        } buttons: {
            if player.sleepTimer != nil {
                TextButton("Turn off") {
                    player.clearSleepTimer()
                    onDismiss()
                }
            }
            TextButton("Close", color: theme.colors.ink2, action: onDismiss)
        }
    }

    private func option(_ text: String, _ action: @escaping () -> Void) -> some View {
        Button {
            action()
            onDismiss()
        } label: {
            Text(text)
                .font(KFont.bodyLarge)
                .foregroundStyle(theme.colors.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

/** A toast at the bottom of the screen, in the colour of its kind. */
struct ToastView: View {
    @Environment(\.kultr) private var theme
    let message: UiMessage

    var body: some View {
        let c = theme.colors
        let color: Color = {
            switch message.kind {
            case .error: return c.danger
            case .warning: return c.warning
            case .success, .info: return c.ink
            }
        }()
        Text(message.text)
            .font(KFont.bodyMedium)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(c.elevated))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
            .padding(.horizontal, 12)
            .onTapGesture { AppGraph.shared.messages.dismiss() }
    }
}
