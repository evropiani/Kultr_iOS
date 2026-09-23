import SwiftUI

struct DownloadsScreen: View {
    @Environment(\.kultr) private var theme
    let initialPage: DownloadsPage
    @State private var page: DownloadsPage?
    @State private var usage = DownloadUsage(count: 0, bytes: 0)

    var body: some View {
        let graph = AppGraph.shared
        let current = page ?? initialPage
        let pending: Int = {
            switch graph.offline.status {
            case .running(_, let queued): return queued
            case .waiting(let queued, _): return queued
            case .idle: return 0
            }
        }()
        ZStack(alignment: .top) {
            AccentWash()
            VStack(spacing: 0) {
                BackBar(title: "Downloads")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Pill(DownloadsPage.now.label, icon: "arrow.down.circle", accent: current == .now, badge: pending > 0 ? "\(pending)" : nil) {
                            page = .now
                        }
                        Pill(DownloadsPage.offline.label, icon: "checkmark.circle", accent: current == .offline, badge: usage.count > 0 ? "\(usage.count)" : nil) {
                            page = .offline
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
                Group {
                    switch current {
                    case .now: DownloadQueue()
                    case .offline: OfflineContent()
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .kultrScreen()
        .onChange(of: initialPage) { _, value in page = value }
        .task(id: "\(graph.library.downloadsVersion):\(graph.offline.downloadedIds.count)") { usage = graph.offline.usage() }
    }
}

// --------------------------------------------------------------- queue --

private struct DownloadQueue: View {
    @Environment(\.kultr) private var theme
    @State private var queue: [DownloadRow] = []
    @State private var failed: [DownloadRow] = []
    @State private var songs: [String: Song] = [:]
    @State private var confirmStop = false

    var body: some View {
        let graph = AppGraph.shared
        let offline = graph.offline
        let c = theme.colors
        let settings = theme.settings
        // Tracks currently being fetched are shown above, not again in the queue.
        let waiting = queue.filter { offline.active[$0.songId] == nil }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                GlassPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        statusContent
                        Text(settings.offlineWifiOnly ? "Downloads use Wi-Fi only. Change it in Settings → Offline." : "Downloads use Wi-Fi and mobile data.")
                            .font(KFont.labelSmall)
                            .foregroundStyle(c.ink3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if !offline.active.isEmpty {
                    SectionHeader("Now", icon: "arrow.down.circle")
                    ForEach(offline.active.values.sorted { $0.song.id < $1.song.id }, id: \.song.id) { ActiveRow(item: $0) }
                }

                if !waiting.isEmpty {
                    SectionHeader("Up next") {
                        Text(Format.count(max(offline.queuedCount - offline.active.count, waiting.count), "track"))
                            .font(KFont.bodySmall)
                            .foregroundStyle(c.ink3)
                    }
                    ForEach(waiting, id: \.songId) { row in
                        QueuedRow(song: songs[row.songId], songId: row.songId, error: nil) {
                            Task { await offline.dequeue([row.songId]) }
                        }
                    }
                    let hidden = offline.queuedCount - offline.active.count - waiting.count
                    if hidden > 0 {
                        Text("…and \(Format.count(hidden, "more track"))")
                            .font(KFont.bodySmall)
                            .foregroundStyle(c.ink3)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                }

                if !failed.isEmpty {
                    SectionHeader("Failed", icon: "exclamationmark.circle") {
                        HStack(spacing: 6) {
                            Pill("Retry all", icon: "arrow.clockwise") {
                                Task {
                                    let count = await offline.retryFailed()
                                    graph.messages.show("Trying \(Format.count(count, "track")) again.")
                                }
                            }
                            Pill("Clear") { Task { await offline.clearFailed() } }
                        }
                    }
                    ForEach(failed, id: \.songId) { row in
                        QueuedRow(song: songs[row.songId], songId: row.songId, error: row.error ?? "Failed") {
                            Task { await offline.dequeue([row.songId]) }
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .task(id: "\(graph.library.downloadsVersion):\(offline.queuedCount):\(offline.active.count)") {
            queue = offline.queuedRows(200)
            failed = offline.failedRows()
            let ids = (queue + failed).map { $0.songId }.filter { songs[$0] == nil }
            if !ids.isEmpty {
                for song in await graph.library.songsByIds(ids) { songs[song.id] = song }
            }
        }
        .alert("Stop downloading?", isPresented: $confirmStop) {
            Button("Cancel", role: .cancel) {}
            Button("Stop", role: .destructive) { offline.cancel() }
        } message: {
            Text("Everything still waiting is taken out of the queue. Tracks already downloaded stay on this phone.")
        }
    }

    @ViewBuilder private var statusContent: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        switch graph.offline.status {
        case .running(let p, let queued):
            if let p, p.total > 0 {
                Text("Downloading \(min(p.total, p.done + p.failed + 1)) of \(p.total)").font(KFont.titleMedium).foregroundStyle(c.ink)
                ProgressBar(value: Double(p.done + p.failed) / Double(p.total))
                Text(
                    "\(p.done) done · \(Format.bytes(p.bytes))"
                        + (p.failed > 0 ? " · \(p.failed) failed" : "")
                        + (queued > 0 ? " · \(queued) to go" : "")
                )
                .font(KFont.bodySmall)
                .foregroundStyle(c.ink3)
            } else {
                Text("Downloading…").font(KFont.titleMedium).foregroundStyle(c.ink)
                ProgressBar(value: nil)
            }
            Pill("Stop", icon: "stop.fill") { confirmStop = true }
        case .waiting(let queued, let forWifi):
            HStack(spacing: 10) {
                Image(systemName: forWifi ? "wifi" : "icloud.slash").foregroundStyle(c.warning)
                Text(forWifi ? "\(Format.count(queued, "track")) waiting for Wi-Fi" : "\(Format.count(queued, "track")) waiting for a connection")
                    .font(KFont.titleMedium)
                    .foregroundStyle(c.ink)
            }
            Text(
                forWifi
                    ? "“Download on Wi-Fi only” is on, and this phone is on mobile data. Downloads start by themselves once you are on Wi-Fi and Kultr is open."
                    : "Downloads start by themselves once the phone is online."
            )
            .font(KFont.bodySmall)
            .foregroundStyle(c.ink2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if forWifi || theme.settings.offlineWifiOnly {
                        Pill("Use mobile data too", icon: "antenna.radiowaves.left.and.right", accent: true) {
                            graph.settings.update { $0.offlineWifiOnly = false }
                        }
                    } else {
                        Pill("Try now", icon: "arrow.clockwise", accent: true) { graph.offline.startWorker(force: true) }
                    }
                    Pill("Clear queue", icon: "xmark") { confirmStop = true }
                }
            }
        case .idle:
            Text("Nothing is downloading").font(KFont.titleMedium).foregroundStyle(c.ink)
            Text("Use Download on an album, artist or playlist — or drag anything onto “Sync offline” — to keep it on this phone.")
                .font(KFont.bodySmall)
                .foregroundStyle(c.ink2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Pill("Download favourites", icon: "arrow.down.circle") {
                        Task { await graph.offline.download(await graph.library.starredSongsNow(), label: "Your favourites") }
                    }
                    Pill("Download everything", icon: "arrow.down.circle") {
                        Task { await graph.offline.download(await graph.library.allSongs(), label: "Your library") }
                    }
                }
            }
        }
    }
}

private struct ActiveRow: View {
    @Environment(\.kultr) private var theme
    let item: ActiveDownload

    var body: some View {
        let c = theme.colors
        HStack(spacing: 12) {
            Artwork(coverId: item.song.artworkId, size: 44, label: item.song.album)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.song.title).font(KFont.bodyLarge.weight(.semibold)).foregroundStyle(c.ink).lineLimit(1)
                ProgressBar(value: item.fraction)
                Text(item.total > 0 ? "\(Format.bytes(item.bytes)) of \(Format.bytes(item.total))" : Format.bytes(item.bytes))
                    .font(KFont.labelSmall)
                    .foregroundStyle(c.ink3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

private struct QueuedRow: View {
    @Environment(\.kultr) private var theme
    let song: Song?
    let songId: String
    let error: String?
    let onRemove: () -> Void

    var body: some View {
        let c = theme.colors
        HStack(spacing: 12) {
            Artwork(coverId: song?.artworkId, size: 40, label: song?.album)
            VStack(alignment: .leading, spacing: 2) {
                Text(song?.title ?? songId).foregroundStyle(c.ink).lineLimit(1)
                Text(error ?? [song?.artist, song?.album].compactMap { $0 }.joined(separator: " · "))
                    .font(KFont.bodySmall)
                    .foregroundStyle(error != nil ? c.danger : c.ink3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            IconButton(icon: "xmark", tint: c.ink3, label: "Remove from the queue", action: onRemove)
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
    }
}

// ------------------------------------------------------------- offline --

/** What is on this phone: albums with downloaded tracks, then every track. */
struct OfflineContent: View {
    @Environment(\.kultr) private var theme
    @State private var songs: [Song] = []
    @State private var albums: [Album] = []
    @State private var usage = DownloadUsage(count: 0, bytes: 0)
    @State private var selection = SongSelection()
    @State private var confirmClear = false

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        VStack(spacing: 0) {
            if selection.active { SelectionBar(selection: selection, songs: songs) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(Format.count(usage.count, "track")) on this phone · \(Format.bytes(usage.bytes))")
                            .font(KFont.titleMedium)
                            .foregroundStyle(c.ink)
                        DownloadIndicator(inline: true)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Pill("Play", icon: "play.fill", accent: true, enabled: !songs.isEmpty) { graph.actions.play(songs) }
                                Pill("Shuffle", icon: "shuffle", enabled: !songs.isEmpty) { graph.actions.shuffle(songs) }
                                Pill("Remove all", icon: "trash", enabled: usage.count > 0) { confirmClear = true }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    if songs.isEmpty {
                        EmptyState(
                            icon: "checkmark.icloud",
                            title: "Nothing on this phone yet",
                            message: "Use Download on any album, artist, playlist or track — or drag it onto “Sync offline” — to keep it here for when you have no connection."
                        )
                    } else {
                        if !albums.isEmpty {
                            SectionHeader("Albums") {
                                Text(Format.count(albums.count, "album")).font(KFont.bodySmall).foregroundStyle(c.ink3)
                            }
                            Shelf(items: albums) { AlbumCard(album: $0) }
                        }
                        SectionHeader("Tracks")
                        SongRows(songs: songs, selection: selection, keyPrefix: "offline") { graph.actions.play(songs, $0) }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .task(id: "\(graph.library.downloadsVersion):\(graph.offline.downloadedIds.count):\(graph.library.version)") {
            usage = graph.offline.usage()
            let loaded = await graph.library.songsByIds(Array(graph.offline.downloadedIds))
            let sorted = loaded.sorted { a, b in
                let artistA = (a.artist ?? "").lowercased(), artistB = (b.artist ?? "").lowercased()
                if artistA != artistB { return artistA < artistB }
                let albumA = (a.album ?? "").lowercased(), albumB = (b.album ?? "").lowercased()
                if albumA != albumB { return albumA < albumB }
                if (a.discNumber ?? 0) != (b.discNumber ?? 0) { return (a.discNumber ?? 0) < (b.discNumber ?? 0) }
                return (a.track ?? 0) < (b.track ?? 0)
            }
            var order: [String] = []
            var groups: [String: [Song]] = [:]
            for song in sorted {
                guard let albumId = song.albumId else { continue }
                if groups[albumId] == nil { order.append(albumId) }
                groups[albumId, default: []].append(song)
            }
            albums = order.compactMap { id in
                guard let tracks = groups[id], let first = tracks.first else { return nil }
                return Album(id: id, name: first.album ?? "", artist: first.artist, artistId: first.artistId, coverArt: first.coverArt, songCount: tracks.count)
            }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
            songs = sorted
        }
        .alert("Remove every download?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Remove all", role: .destructive) {
                Task {
                    let removed = await graph.offline.removeAll()
                    graph.messages.show("Removed \(removed) downloads.")
                }
            }
        } message: {
            Text("The files are deleted from this phone. Your library and playlists are not touched.")
        }
    }
}

// ----------------------------------------------------------- indicator --

/**
 * A strip that shows while anything is downloading or waiting to. Tapping it
 * opens the Downloads page. [inline] drops the outer margins for use inside
 * a page.
 */
struct DownloadIndicator: View {
    @Environment(\.kultr) private var theme
    var inline = false

    var body: some View {
        let graph = AppGraph.shared
        let offline = graph.offline
        let c = theme.colors
        let status = offline.status
        if status != .idle {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Group {
                        if case .waiting(_, let forWifi) = status {
                            Image(systemName: forWifi ? "wifi" : "icloud.slash").foregroundStyle(c.warning)
                        } else {
                            Image(systemName: "arrow.down.circle").foregroundStyle(c.accent)
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    Text(label(status, offline.active))
                        .font(KFont.bodyMedium)
                        .foregroundStyle(c.ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(c.ink3)
                }
                if case .running(let p, _) = status {
                    if let p, p.total > 0 {
                        let fractions = offline.active.values.map { $0.fraction }
                        let within = fractions.isEmpty ? 0 : fractions.reduce(0, +) / Double(fractions.count)
                        ProgressBar(value: min(1, max(0, (Double(p.done + p.failed) + within * Double(min(1, offline.active.count))) / Double(p.total))), height: 3)
                    } else {
                        ProgressBar(value: nil, height: 3)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous)
                    .fill(c.elevated.opacity(0.94))
                    .overlay(RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous).fill(c.accent.opacity(0.08)))
            )
            .contentShape(Rectangle())
            .onTapGesture { graph.actions.openDownloads(.now) }
            .padding(.horizontal, inline ? 0 : 8)
            .padding(.vertical, inline ? 0 : 2)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func label(_ status: DownloadStatus, _ active: [String: ActiveDownload]) -> String {
        switch status {
        case .running(let p, _):
            let current = active.values.first?.song.title
            if let p, p.total > 0, let current { return "\(min(p.total, p.done + p.failed + 1))/\(p.total) · \(current)" }
            if let p, p.total > 0 { return "Downloading \(p.done + p.failed)/\(p.total)" }
            return "Downloading…"
        case .waiting(let queued, let forWifi):
            return forWifi ? "\(Format.count(queued, "download")) waiting for Wi-Fi" : "\(Format.count(queued, "download")) waiting for a connection"
        case .idle:
            return ""
        }
    }
}
