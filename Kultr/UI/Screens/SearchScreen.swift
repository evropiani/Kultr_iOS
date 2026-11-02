import SwiftUI

struct SearchScreen: View {
    @Environment(\.kultr) private var theme
    @State private var counts = LibraryCounts()
    @State private var serverSearch = false
    @State private var results = SearchResults()
    @State private var loading = false
    @State private var error: String?
    @State private var selection = SongSelection()
    @State private var asking = false

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        // The phone's own music is all in the library; only a server has more to ask.
        let local = graph.isLocal
        let useServer = !local && (serverSearch || counts.songs == 0)
        // The field itself lives in the tab bar (see Chrome), where it expands out of the search button.
        let trimmed = graph.ui.searchQuery.trimmingCharacters(in: .whitespaces)
        // A command searches for what it names ("shuffle love" → "love"), or for nothing.
        let command = CommandRunner.parse(trimmed)
        let lookFor = command.map(Self.subject) ?? trimmed
        VStack(alignment: .leading, spacing: 0) {
            if !local {
                HStack {
                    Text(counts.songs == 0 ? "Searching your server (the library is not synced yet)" : "Search on the server instead")
                        .font(KFont.bodySmall)
                        .foregroundStyle(c.ink3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if counts.songs > 0 {
                        KultrSwitch(isOn: serverSearch) { serverSearch = $0 }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            SelectionBar(selection: selection, songs: results.songs)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // The command bar: words Kultr can do, above what it finds.
                    if let command = CommandRunner.parse(trimmed) {
                        CommandRow(command: command) { run(command) }
                    } else if CommandRunner.canInterpret, trimmed.split(separator: " ").count >= 3 {
                        AskRow(text: trimmed, asking: asking) { ask(trimmed) }
                    }
                    if trimmed.count < 2 {
                        EmptyState(
                            icon: "magnifyingglass",
                            title: "Find anything, or say what to do",
                            message: "Type at least two letters. Or try “play Night Drive”, “shuffle” and an artist, “sleep in 30 minutes”, “next” or “plan an hour”."
                        )
                    } else if loading && results.isEmpty {
                        SkeletonRows(count: 8)
                    } else if let error {
                        EmptyState(icon: "icloud.slash", title: "Search failed", message: error)
                    } else if results.isEmpty && command != nil {
                        EmptyView()
                    } else if results.isEmpty {
                        EmptyState(icon: "magnifyingglass", title: "Nothing matches “\(trimmed)”", message: "Check the spelling, or try fewer words.")
                    } else {
                        if !results.artists.isEmpty {
                            SectionHeader("Artists")
                            Shelf(items: results.artists, cardWidth: 120) { ArtistCard(artist: $0) }
                        }
                        if !results.albums.isEmpty {
                            SectionHeader("Albums")
                            Shelf(items: results.albums) { AlbumCard(album: $0) }
                        }
                        if !results.songs.isEmpty {
                            SectionHeader("Tracks")
                            SongRows(songs: results.songs, selection: selection) { graph.actions.play(results.songs, $0) }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .navigationTitle("Search")
        .kultrScreen()
        .onSubmit(of: .search) {
            if let command = CommandRunner.parse(trimmed) {
                run(command)
            } else if CommandRunner.canInterpret, trimmed.split(separator: " ").count >= 3 {
                ask(trimmed)
            }
        }
        .task(id: graph.library.version) { counts = await graph.library.counts() }
        .task(id: "\(lookFor)|\(useServer)") {
            let trimmed = lookFor
            guard trimmed.count >= 2 else {
                results = SearchResults()
                error = nil
                loading = false
                return
            }
            try? await Task.sleep(nanoseconds: useServer ? 350_000_000 : 120_000_000)
            if Task.isCancelled { return }
            loading = true
            error = nil
            do {
                let found: SearchResults
                if useServer {
                    found = try await graph.library.searchServer(trimmed)
                } else {
                    found = await graph.library.search(trimmed)
                }
                if Task.isCancelled { return }
                results = found
            } catch {
                if Task.isCancelled { return }
                self.error = describeError(error)
                results = SearchResults()
            }
            loading = false
        }
    }

    /** What a command names, to show search results for it under its row. */
    private static func subject(_ command: KultrCommand) -> String {
        switch command {
        case .play(let what), .shuffle(let what): return what
        default: return ""
        }
    }

    private func run(_ command: KultrCommand) {
        Haptics.tap()
        Task {
            await CommandRunner.run(command)
            AppGraph.shared.ui.searchQuery = ""
        }
    }

    private func ask(_ text: String) {
        guard !asking else { return }
        asking = true
        Task {
            let command = await CommandRunner.interpret(text)
            asking = false
            if let command {
                AppGraph.shared.messages.show(CommandRunner.describe(command).text)
                run(command)
            } else {
                AppGraph.shared.messages.show("Kultr didn't understand that one. Try “play” and an artist, or “sleep in 30 minutes”.")
            }
        }
    }
}

/** A command the words make: tap it, or press Return, and Kultr does it. */
private struct CommandRow: View {
    @Environment(\.kultr) private var theme
    let command: KultrCommand
    let action: () -> Void

    var body: some View {
        let c = theme.colors
        let what = CommandRunner.describe(command)
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: what.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(c.onAccent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(c.accent))
                VStack(alignment: .leading, spacing: 2) {
                    Text(what.text)
                        .font(KFont.bodyLarge.weight(.semibold))
                        .foregroundStyle(c.ink)
                        .lineLimit(2)
                    Text("Tap, or press Return")
                        .font(KFont.bodySmall)
                        .foregroundStyle(c.ink3)
                }
                Spacer(minLength: 0)
                Image(systemName: "return")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(c.ink3)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(c.sand))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityHint("Does it now")
    }
}

/** Words the rules didn't understand, with Apple Intelligence on: ask the on-device model. */
private struct AskRow: View {
    @Environment(\.kultr) private var theme
    let text: String
    let asking: Bool
    let action: () -> Void

    var body: some View {
        let c = theme.colors
        Button(action: action) {
            HStack(spacing: 12) {
                Group {
                    if asking {
                        ProgressView().tint(c.accent)
                    } else {
                        Image(systemName: "apple.intelligence")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(c.accent)
                    }
                }
                .frame(width: 40, height: 40)
                .background(Circle().fill(c.accentSoft))
                VStack(alignment: .leading, spacing: 2) {
                    Text(asking ? "Working it out…" : "Ask Kultr to do it")
                        .font(KFont.bodyLarge.weight(.semibold))
                        .foregroundStyle(c.ink)
                    Text("Read on this iPhone by Apple Intelligence; nothing is sent anywhere.")
                        .font(KFont.bodySmall)
                        .foregroundStyle(c.ink3)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(c.ink4, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(asking)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
