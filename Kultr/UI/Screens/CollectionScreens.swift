import SwiftUI

// ---------------------------------------------------------- notes and tags --

/**
 * "Your notes" on an album or artist page: tags you can tap to see everything
 * with that tag, and a note of your own. Private; kept with your settings.
 */
struct AnnotationSection: View {
    @Environment(\.kultr) private var theme
    let key: String
    let name: String
    @State private var addingTag = false
    @State private var newTag = ""
    @State private var editingNote = false

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        let annotation = theme.settings.annotations[key] ?? Annotation()
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Your notes")
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(annotation.tags, id: \.self) { tag in
                            Button { graph.actions.openTag(tag) } label: {
                                Label(tag, systemImage: "tag.fill")
                                    .font(KFont.labelLarge)
                                    .foregroundStyle(c.accent)
                                    .padding(.horizontal, 12)
                                    .frame(height: 32)
                                    .background(Capsule().fill(c.sand))
                            }
                            .buttonStyle(PressScaleStyle())
                            .contextMenu {
                                Button { graph.actions.openTag(tag) } label: { Label("Everything tagged “\(tag)”", systemImage: "tag") }
                                Button(role: .destructive) {
                                    var changed = annotation
                                    changed.removeTag(tag)
                                    graph.crates.setAnnotation(key, changed)
                                } label: { Label("Remove the tag", systemImage: "minus.circle") }
                            }
                        }
                        Button {
                            newTag = ""
                            addingTag = true
                        } label: {
                            Label("Tag", systemImage: "plus")
                                .font(KFont.labelLarge)
                                .foregroundStyle(c.ink2)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .overlay(Capsule().strokeBorder(c.ink4, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        }
                        .buttonStyle(PressScaleStyle())
                        .accessibilityLabel("Add a tag")
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.horizontal, -16)

                Button { editingNote = true } label: {
                    Group {
                        if annotation.note.isEmpty {
                            Label("Add a note", systemImage: "square.and.pencil")
                                .foregroundStyle(c.ink3)
                        } else {
                            Text(annotation.note)
                                .foregroundStyle(c.ink)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .font(KFont.bodyMedium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(c.sand.opacity(0.6)))
                }
                .buttonStyle(PressableStyle())
                .accessibilityHint("Edits your note")
            }
            .padding(.horizontal, 16)
        }
        .alert("Tag “\(name)”", isPresented: $addingTag) {
            TextField("Tag", text: $newTag)
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                var changed = annotation
                changed.addTag(newTag)
                graph.crates.setAnnotation(key, changed)
            }
            .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            let existing = tagCounts(theme.settings.annotations).prefix(6).map(\.tag).filter { tag in !annotation.tags.contains(tag) }
            Text(existing.isEmpty ? "A word of your own, like “gym” or “rainy day”." : "Tags you use: " + existing.joined(separator: ", "))
        }
        .sheet(isPresented: $editingNote) {
            NoteEditor(name: name, text: annotation.note) { text in
                var changed = annotation
                changed.note = text.trimmingCharacters(in: .whitespacesAndNewlines)
                graph.crates.setAnnotation(key, changed)
                editingNote = false
            } onCancel: {
                editingNote = false
            }
            .environment(\.kultr, theme)
        }
    }
}

private struct NoteEditor: View {
    @Environment(\.kultr) private var theme
    let name: String
    @State var text: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($focused)
                .font(KFont.bodyLarge)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(theme.colors.background)
                .navigationTitle(name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(text) } }
                }
                .onAppear { focused = true }
        }
        .tint(theme.colors.accent)
    }
}

/** Library → Tags: every tag you use, with how many albums and artists carry it. */
struct TagsTab: View {
    @Environment(\.kultr) private var theme
    let query: String

    var body: some View {
        let c = theme.colors
        let tags = tagCounts(theme.settings.annotations).filter { query.isEmpty || $0.tag.lowercased().contains(query) }
        ScrollView {
            if tags.isEmpty {
                EmptyState(
                    icon: "tag",
                    title: query.isEmpty ? "No tags yet" : "No tags match “\(query)”",
                    message: "Open an album or an artist and tap + Tag under Your notes."
                )
                .padding(.top, 24)
            }
            LazyVStack(spacing: 0) {
                ForEach(tags, id: \.tag) { entry in
                    Button { AppGraph.shared.actions.openTag(entry.tag) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "tag.fill").foregroundStyle(c.accent).frame(width: 28)
                            Text(entry.tag).font(KFont.bodyLarge).foregroundStyle(c.ink)
                            Spacer()
                            Text("\(entry.count)").font(KFont.bodySmall.monospacedDigit()).foregroundStyle(c.ink3)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(c.ink4)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.bottom, 24)
        }
    }
}

/** Everything with one tag: albums and artists, and a way to play them all or make a crate of them. */
struct TagScreen: View {
    @Environment(\.kultr) private var theme
    let tag: String
    @State private var albums: [Album] = []
    @State private var artists: [Artist] = []
    @State private var loaded = false

    var body: some View {
        let graph = AppGraph.shared
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if loaded && albums.isEmpty && artists.isEmpty {
                    EmptyState(icon: "tag", title: "Nothing tagged “\(tag)”", message: "The tag was taken off everything that had it.")
                        .padding(.top, 24)
                } else if !loaded {
                    SkeletonGrid(count: 6)
                } else {
                    HStack(spacing: 12) {
                        WideButton(title: "Play", icon: "play.fill", prominent: true) { Task { graph.actions.play(await songs()) } }
                        WideButton(title: "Shuffle", icon: "shuffle", prominent: false) { Task { graph.actions.shuffle(await songs()) } }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    if !albums.isEmpty {
                        SectionHeader("Albums")
                        Shelf(items: albums) { AlbumCard(album: $0) }
                    }
                    if !artists.isEmpty {
                        SectionHeader("Artists")
                        Shelf(items: artists, cardWidth: 130) { ArtistCard(artist: $0) }
                    }
                    Pill("Make a crate of everything tagged “\(tag)”", icon: "shippingbox") {
                        let crate = Crate(name: tag.capitalized, rules: Station(name: tag.capitalized, icon: "tag.fill", tags: [tag]))
                        graph.crates.save(crate)
                        graph.actions.openCrate(crate.id)
                    }
                    .padding(16)
                }
            }
            .padding(.bottom, 24)
        }
        .navigationTitle(tag)
        .navigationBarTitleDisplayMode(.large)
        .kultrScreen()
        .task(id: "\(theme.settings.annotations.hashValue):\(graph.library.version)") { await load() }
    }

    private func load() async {
        let library = AppGraph.shared.library
        let annotations = theme.settings.annotations
        let wanted = tag.lowercased()
        var foundAlbums: [Album] = []
        var foundArtists: [Artist] = []
        for (key, annotation) in annotations where annotation.tags.contains(where: { $0.lowercased() == wanted }) {
            if key.hasPrefix("album:"), let album = await library.album(String(key.dropFirst(6))) { foundAlbums.append(album) }
            if key.hasPrefix("artist:"), let artist = await library.artist(String(key.dropFirst(7))) { foundArtists.append(artist) }
        }
        albums = foundAlbums.sorted { Format.sortKey($0.name) < Format.sortKey($1.name) }
        artists = foundArtists.sorted { Format.sortKey($0.name) < Format.sortKey($1.name) }
        loaded = true
    }

    private func songs() async -> [Song] {
        let library = AppGraph.shared.library
        var out: [Song] = []
        for album in albums { out += await library.songsOfAlbumNow(album.id) }
        for artist in artists { out += await library.songsOfArtistNow(artist.id) }
        var seen = Set<String>()
        return out.filter { seen.insert($0.id).inserted }
    }
}

// ------------------------------------------------------------------ crates --

/** Library → Crates: your crates as cards, and a button for a new one. */
struct CratesTab: View {
    @Environment(\.kultr) private var theme
    let query: String
    @State private var creating = false
    @State private var newName = ""
    @State private var rulesDraft: StationDraft?

    var body: some View {
        let graph = AppGraph.shared
        let crates = theme.settings.crates.filter { query.isEmpty || $0.name.lowercased().contains(query) }
        ScrollView {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Menu {
                        Button {
                            newName = ""
                            creating = true
                        } label: { Label("Fill it by hand", systemImage: "hand.point.up.left") }
                        Button {
                            rulesDraft = StationDraft(station: Station(name: "New crate", icon: "shippingbox.fill", minRating: 4, addedDays: 365), isNew: true, noun: "crate")
                        } label: { Label("Fill it by rules", systemImage: "slider.horizontal.3") }
                    } label: {
                        PillLabel(text: "New crate", icon: "plus")
                    }
                    Spacer()
                }
                .padding(.bottom, 12)
                if crates.isEmpty {
                    EmptyState(
                        icon: "shippingbox",
                        title: query.isEmpty ? "No crates yet" : "No crates match “\(query)”",
                        message: "A crate holds albums, artists and tracks you choose: hold any of them and tap Add to crate. Or let rules fill it, like “4 stars and up, added this year”."
                    )
                    .padding(.top, 24)
                } else {
                    LazyVGrid(columns: theme.settings.gridSize.columns, spacing: 16) {
                        ForEach(crates) { CrateCard(crate: $0) }
                    }
                }
            }
            .padding(16)
        }
        .alert("New crate", isPresented: $creating) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let crate = Crate(name: newName.trimmingCharacters(in: .whitespaces))
                graph.crates.save(crate)
                graph.messages.show("Hold an album, artist or track and tap Add to crate to fill “\(crate.name)”.")
            }
            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .sheet(item: $rulesDraft) { draft in
            StationEditor(draft: draft) { rules in
                var crate = Crate(name: rules.name, icon: rules.icon, rules: rules)
                crate.rules?.name = rules.name
                graph.crates.save(crate)
                rulesDraft = nil
                graph.actions.openCrate(crate.id)
            } onCancel: {
                rulesDraft = nil
            }
            .environment(\.kultr, theme)
        }
    }
}

/** A crate as a card: up to four covers from what is in it. */
private struct CrateCard: View {
    @Environment(\.kultr) private var theme
    let crate: Crate
    @State private var covers: [String] = []

    var body: some View {
        let c = theme.colors
        CardLayout(title: crate.name, subtitle: crate.byRules ? (crate.rules?.summary ?? "") : crate.contents) {
            ZStack {
                RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous).fill(c.sand)
                if covers.isEmpty {
                    Image(systemName: crate.icon)
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(c.accent)
                } else {
                    let grid = Array(covers.prefix(4))
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
                        ForEach(Array(grid.enumerated()), id: \.offset) { _, cover in
                            ArtworkFill(coverId: cover, radius: 0)
                                .aspectRatio(1, contentMode: .fill)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous))
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .contentShape(Rectangle())
        .onTapGesture { AppGraph.shared.actions.openCrate(crate.id) }
        .contextMenu {
            CollectionMenuItems(name: crate.name) { await AppGraph.shared.crates.songs(crate) }
            Divider()
            Button(role: .destructive) { AppGraph.shared.crates.delete(crate) } label: { Label("Delete the crate", systemImage: "trash") }
        }
        .task(id: crate.hashValue) {
            if crate.byRules {
                let songs = await AppGraph.shared.crates.songs(crate)
                var seen = Set<String>()
                covers = songs.compactMap { $0.coverArt ?? $0.albumId }.filter { seen.insert($0).inserted }
            } else {
                var found: [String] = crate.albums
                for id in crate.songs.prefix(8) where found.count < 4 {
                    if let song = await AppGraph.shared.library.song(id), let cover = song.coverArt ?? song.albumId, !found.contains(cover) {
                        found.append(cover)
                    }
                }
                covers = found
            }
        }
    }
}

/** One crate: play it, see what is in it, change its rules, keep it as a playlist. */
struct CrateScreen: View {
    @Environment(\.kultr) private var theme
    let id: String
    @State private var albums: [Album] = []
    @State private var artists: [Artist] = []
    @State private var songs: [Song] = []
    @State private var handPicked: [Song] = []
    @State private var loaded = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var rulesDraft: StationDraft?
    @State private var confirmDelete = false
    @State private var selection = SongSelection()

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        Group {
            if let crate = theme.settings.crates.first(where: { $0.id == id }) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(crate.byRules ? (crate.rules?.summary ?? "") : crate.contents)
                                .font(KFont.bodyMedium)
                                .foregroundStyle(c.ink2)
                            Text(loaded ? Format.count(songs.count, "track") : "Counting…")
                                .font(KFont.bodySmall)
                                .foregroundStyle(c.ink3)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        HStack(spacing: 12) {
                            WideButton(title: "Play", icon: "play.fill", prominent: true, enabled: !songs.isEmpty) { graph.actions.play(songs) }
                            WideButton(title: "Shuffle", icon: "shuffle", prominent: false, enabled: !songs.isEmpty) { graph.actions.shuffle(songs) }
                        }
                        .padding(16)
                        Group {
                            Toggle(isOn: Binding(get: { crate.syncPlaylist }, set: { on in
                                var changed = crate
                                changed.syncPlaylist = on
                                graph.crates.save(changed)
                                if on { graph.messages.show("“\(crate.name)” will be kept as a playlist") }
                            })) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Keep as a playlist").font(KFont.bodyLarge).foregroundStyle(c.ink)
                                    Text(graph.isLocal
                                        ? "A playlist on this phone with the same tracks, updated when the crate changes."
                                        : "A playlist on your server with the same tracks, so other apps see it too. Updated when the crate changes.")
                                        .font(KFont.bodySmall)
                                        .foregroundStyle(c.ink3)
                                }
                            }
                            .tint(c.accent)
                            .padding(.horizontal, 16)
                        }
                        if crate.byRules {
                            SectionHeader("Tracks")
                            if !loaded { SkeletonRows(count: 8) }
                            SongRows(songs: songs, selection: selection) { graph.actions.playWindow(songs, $0) }
                        } else {
                            if loaded && crate.isEmpty {
                                EmptyState(
                                    icon: "shippingbox",
                                    title: "Nothing in this crate yet",
                                    message: "Hold an album, an artist or a track anywhere in Kultr and tap Add to crate."
                                )
                                .padding(.top, 24)
                            }
                            if !albums.isEmpty {
                                SectionHeader("Albums")
                                Shelf(items: albums) { AlbumCard(album: $0) }
                            }
                            if !artists.isEmpty {
                                SectionHeader("Artists")
                                Shelf(items: artists, cardWidth: 130) { ArtistCard(artist: $0) }
                            }
                            if !handPicked.isEmpty {
                                SectionHeader("Tracks")
                                SongRows(songs: handPicked, selection: selection, keyPrefix: "crate") { graph.actions.play(handPicked, $0) }
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
                .navigationTitle(crate.name)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                newName = crate.name
                                renaming = true
                            } label: { Label("Rename…", systemImage: "pencil") }
                            if let rules = crate.rules {
                                Button {
                                    var draft = rules
                                    draft.name = crate.name
                                    draft.icon = crate.icon
                                    rulesDraft = StationDraft(station: draft, isNew: false, noun: "crate")
                                } label: { Label("Change the rules…", systemImage: "slider.horizontal.3") }
                                Button {
                                    var station = rules
                                    station.id = UUID().uuidString
                                    station.name = crate.name
                                    station.icon = crate.icon
                                    graph.stations.save(station)
                                    graph.messages.show("“\(crate.name)” is a station too now")
                                } label: { Label("Make it a station", systemImage: "dial.medium") }
                            }
                            if crate.syncPlaylist {
                                Button { Task { if await graph.crates.syncNow(crate.id) == nil { graph.messages.show("Playlist up to date") } } } label: {
                                    Label("Update the playlist now", systemImage: "arrow.clockwise")
                                }
                            }
                            Button { graph.actions.addToPlaylist(songs) } label: { Label("Add to playlist…", systemImage: "text.badge.plus") }
                            Divider()
                            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete the crate", systemImage: "trash") }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("More")
                    }
                }
                .task(id: "\(crate.hashValue):\(graph.library.version):\(theme.settings.annotations.hashValue)") { await load(crate) }
                .alert("Rename the crate", isPresented: $renaming) {
                    TextField("Name", text: $newName)
                    Button("Cancel", role: .cancel) {}
                    Button("Rename") {
                        var changed = crate
                        changed.name = newName.trimmingCharacters(in: .whitespaces)
                        graph.crates.save(changed)
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .alert("Delete “\(crate.name)”?", isPresented: $confirmDelete) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) {
                        graph.crates.delete(crate)
                        graph.actions.back()
                    }
                } message: {
                    Text(crate.playlistId == nil ? "The music stays in your library." : "The music stays in your library, and so does its playlist.")
                }
                .sheet(item: $rulesDraft) { draft in
                    StationEditor(draft: draft) { rules in
                        var changed = crate
                        changed.rules = rules
                        changed.name = rules.name
                        changed.icon = rules.icon
                        graph.crates.save(changed)
                        rulesDraft = nil
                    } onCancel: {
                        rulesDraft = nil
                    }
                    .environment(\.kultr, theme)
                }
            } else {
                EmptyState(icon: "shippingbox", title: "This crate is gone", message: "It was deleted.")
                    .frame(maxHeight: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.large)
        .kultrScreen()
    }

    private func load(_ crate: Crate) async {
        let graph = AppGraph.shared
        songs = await graph.crates.songs(crate)
        if !crate.byRules {
            var foundAlbums: [Album] = []
            for id in crate.albums { if let album = await graph.library.album(id) { foundAlbums.append(album) } }
            var foundArtists: [Artist] = []
            for id in crate.artists { if let artist = await graph.library.artist(id) { foundArtists.append(artist) } }
            albums = foundAlbums
            artists = foundArtists
            handPicked = await graph.library.songsByIds(crate.songs)
        }
        loaded = true
    }
}

/** "Add to crate": every crate filled by hand, ticked where the item is in it already, and a new one. */
struct AddToCrateSheet: View {
    @Environment(\.kultr) private var theme
    let item: CrateItem
    let onDismiss: () -> Void
    @State private var creating = false
    @State private var newName = ""

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        let crates = theme.settings.crates.filter { !$0.byRules }
        SheetScaffold(title: "Add “\(item.title)” to a crate") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        newName = ""
                        creating = true
                    } label: {
                        Label("New crate…", systemImage: "plus")
                            .font(KFont.bodyLarge.weight(.semibold))
                            .foregroundStyle(c.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    ForEach(crates) { crate in
                        let inside = graph.crates.contains(crate, item)
                        Button { graph.crates.toggle(item, in: crate.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: crate.icon).foregroundStyle(c.accent).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(crate.name).font(KFont.bodyLarge).foregroundStyle(c.ink)
                                    Text(crate.contents).font(KFont.bodySmall).foregroundStyle(c.ink3)
                                }
                                Spacer()
                                Image(systemName: inside ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(inside ? c.accent : c.ink4)
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityAddTraits(inside ? .isSelected : [])
                    }
                }
            }
        } buttons: {
            TextButton("Done", action: onDismiss)
        }
        .alert("New crate", isPresented: $creating) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let crate = Crate(name: newName.trimmingCharacters(in: .whitespaces))
                graph.crates.save(crate)
                graph.crates.toggle(item, in: crate.id)
            }
            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
