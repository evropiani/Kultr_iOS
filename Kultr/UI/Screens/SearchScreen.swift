import SwiftUI

struct SearchScreen: View {
    @Environment(\.kultr) private var theme
    @State private var counts = LibraryCounts()
    @State private var query = ""
    @State private var serverSearch = false
    @State private var results = SearchResults()
    @State private var loading = false
    @State private var error: String?
    @State private var selection = SongSelection()

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        let useServer = serverSearch || counts.songs == 0
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        VStack(alignment: .leading, spacing: 0) {
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
            SelectionBar(selection: selection, songs: results.songs)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if trimmed.count < 2 {
                        EmptyState(icon: "magnifyingglass", title: "Find anything", message: "Type at least two letters.")
                    } else if loading && results.isEmpty {
                        LoadingView()
                    } else if let error {
                        EmptyState(icon: "icloud.slash", title: "Search failed", message: error)
                    } else if results.isEmpty {
                        EmptyState(icon: "magnifyingglass", title: "Nothing matches “\(trimmed)”")
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
        .searchable(text: $query, prompt: "Artists, albums, tracks")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .kultrScreen()
        .task(id: graph.library.version) { counts = await graph.library.counts() }
        .task(id: "\(trimmed)|\(useServer)") {
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
}
