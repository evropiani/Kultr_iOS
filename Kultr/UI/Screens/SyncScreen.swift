import SwiftUI

struct SyncScreen: View {
    @Environment(\.kultr) private var theme
    @State private var counts = LibraryCounts()
    @State private var state = SyncState()
    @State private var analysed = 0
    @State private var missing = 0
    @State private var usage = DownloadUsage(count: 0, bytes: 0)

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        let sync = graph.sync
        let settings = theme.settings
        ZStack(alignment: .top) {
            AccentWash()
            VStack(spacing: 0) {
                BackBar(title: "Sync")
                ScrollView {
                    VStack(spacing: 16) {
                        GlassPanel {
                            VStack(alignment: .leading, spacing: 10) {
                                Eyebrow("Your library on this phone")
                                Text("\(Format.count(counts.artists, "artist")) · \(Format.count(counts.albums, "album")) · \(Format.count(counts.songs, "track"))")
                                    .font(KFont.titleMedium)
                                    .foregroundStyle(c.ink)
                                Text("\(Format.count(counts.playlists, "playlist")) · \(Format.count(counts.genres, "genre"))")
                                    .foregroundStyle(c.ink2)
                                Text("Last checked \(Format.relative(state.lastCheck)) · last full sync \(Format.relative(state.lastFullSync))")
                                    .font(KFont.bodySmall)
                                    .foregroundStyle(c.ink3)
                                connectionLine
                                if sync.running, let p = sync.progress {
                                    ProgressBar(value: p.percent)
                                    Text(p.message).font(KFont.bodySmall).foregroundStyle(c.ink2)
                                } else if !sync.running, sync.progress?.phase == .done, let s = sync.summary {
                                    Text(s.upToDate ? "Everything was already up to date." : "\(s.albumsAdded) albums added, \(s.albumsUpdated) changed, \(s.albumsRemoved) removed.")
                                        .font(KFont.bodySmall)
                                        .foregroundStyle(c.success)
                                    if !s.errors.isEmpty {
                                        Text("\(s.errors.count) albums could not be read: \(s.errors.prefix(3).joined(separator: "; "))")
                                            .font(KFont.bodySmall)
                                            .foregroundStyle(c.warning)
                                    }
                                }
                                if let error = sync.error {
                                    Text(error).font(KFont.bodySmall).foregroundStyle(c.danger)
                                }
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        if sync.running {
                                            Pill("Stop", icon: "stop.fill") { sync.cancel() }
                                        } else {
                                            Pill(counts.albums == 0 ? "Sync my library" : "Check for updates", icon: "arrow.triangle.2.circlepath", accent: true) {
                                                sync.start(counts.albums == 0 ? .full : .check)
                                            }
                                            if counts.albums > 0 {
                                                Pill("Full resync", icon: "icloud.and.arrow.down") { sync.start(.full) }
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GlassPanel {
                            VStack(alignment: .leading, spacing: 4) {
                                Eyebrow("Keeping it fresh")
                                SettingRow("Check when Kultr starts", hint: "Pulls in only what changed.") {
                                    KultrSwitch(isOn: settings.autoSyncOnStart) { v in graph.settings.update { $0.autoSyncOnStart = v } }
                                }
                                SettingRow(
                                    "Check in the background",
                                    hint: settings.autoSyncMinutes > 0 ? "When iOS lets Kultr run, about every \(settings.autoSyncMinutes) minutes." : "Off."
                                ) {
                                    KultrSwitch(isOn: settings.autoSyncMinutes > 0) { v in
                                        graph.settings.update { $0.autoSyncMinutes = v ? 60 : 0 }
                                        sync.scheduleBackgroundCheck()
                                    }
                                }
                                SettingRow("Sync playlist contents", hint: "Reads every playlist's tracks, so they open instantly and offline.") {
                                    KultrSwitch(isOn: settings.syncPlaylistContents) { v in graph.settings.update { $0.syncPlaylistContents = v } }
                                }
                            }
                        }

                        GlassPanel {
                            VStack(alignment: .leading, spacing: 10) {
                                Eyebrow("InjeKt analysis")
                                Text("\(analysed) tracks analysed · \(missing) to go")
                                    .font(KFont.titleMedium)
                                    .foregroundStyle(c.ink)
                                Text("InjeKt measures tempo, key, energy and structure to plan beat-matched transitions. It analyses tracks just before they are needed anyway; doing it up front means every transition is planned from the first play. Each track is streamed once at a low bitrate. Keep Kultr open while it runs.")
                                    .font(KFont.bodySmall)
                                    .foregroundStyle(c.ink2)
                                if let b = graph.analysis.bulkProgress {
                                    ProgressBar(value: b.total > 0 ? Double(b.done) / Double(b.total) : 0)
                                    Text("Analysing “\(b.current)”").font(KFont.bodySmall).foregroundStyle(c.ink3)
                                    Pill("Stop", icon: "stop.fill") { graph.analysis.cancelBulk() }
                                } else {
                                    Pill("Analyse missing", icon: "sparkles", accent: missing > 0, enabled: missing > 0) { graph.analysis.startBulk() }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GlassPanel {
                            VStack(alignment: .leading, spacing: 10) {
                                Eyebrow("Offline")
                                Text("\(Format.count(usage.count, "track")) downloaded · \(Format.bytes(usage.bytes))")
                                    .font(KFont.titleMedium)
                                    .foregroundStyle(c.ink)
                                if let d = graph.offline.progress {
                                    ProgressBar(value: d.total > 0 ? Double(d.done) / Double(d.total) : 0)
                                    Text("\(d.done) of \(d.total)").font(KFont.bodySmall).foregroundStyle(c.ink3)
                                }
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        Pill("Download favourites", icon: "arrow.down.circle") {
                                            Task { await graph.offline.download(await graph.library.starredSongsNow(), label: "Your favourites") }
                                        }
                                        Pill("Download everything", icon: "arrow.down.circle") {
                                            Task { await graph.offline.download(await graph.library.allSongs(), label: "Your library") }
                                        }
                                        Pill("Open downloads") { graph.actions.openDownloads() }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
        }
        .kultrScreen()
        .task(id: graph.library.version) {
            counts = await graph.library.counts()
            state = await graph.library.syncState()
        }
        .task(id: "\(graph.library.analysisVersion):\(graph.library.version)") {
            analysed = await graph.analysis.analysedCount()
            missing = await graph.analysis.missingCount()
        }
        .task(id: "\(graph.library.downloadsVersion):\(graph.offline.downloadedIds.count)") {
            usage = graph.offline.usage()
        }
    }

    @ViewBuilder private var connectionLine: some View {
        let c = theme.colors
        switch AppGraph.shared.auth.connection {
        case .online(let info):
            Text("Connected to \(info.summary)").font(KFont.bodySmall).foregroundStyle(c.ink3)
        case .offline(let message):
            Text("Server unreachable: \(message)").font(KFont.bodySmall).foregroundStyle(c.warning)
        case .connecting:
            Text("Connecting…").font(KFont.bodySmall).foregroundStyle(c.ink3)
        case .idle:
            Text("Not connected").font(KFont.bodySmall).foregroundStyle(c.ink3)
        }
    }
}
