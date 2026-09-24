import SwiftUI

private enum PlayerTab: CaseIterable {
    case queue, lyrics, injekt

    var label: String {
        switch self {
        case .queue: return "Up next"
        case .lyrics: return "Lyrics"
        case .injekt: return "InjeKt"
        }
    }
}

private struct TopOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/** The full-screen player. Pull it down (from the top of its list) to close it. */
struct NowPlayingScreen: View {
    @Environment(\.kultr) private var theme
    @State private var tab: PlayerTab = .queue
    @State private var pull: CGFloat = NowPlayingScreen.initialPull
    @State private var topOffset: CGFloat = 0
    @State private var pulling = false
    @State private var live: Song?

    var body: some View {
        let graph = AppGraph.shared
        let state = graph.player.state
        let settings = theme.settings
        ZStack {
            if let song = state.current {
                let current = live?.id == song.id ? live! : song
                ScrollView {
                    VStack(spacing: 0) {
                        PlayerTopBar(song: current, onClose: close)
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(key: TopOffsetKey.self, value: proxy.frame(in: .named("player")).minY)
                                }
                            )
                        header(current, state: state, settings: settings)
                        Picker("Show", selection: Binding(get: { tab }, set: { value in withAnimation(theme.ease) { tab = value } })) {
                            ForEach(PlayerTab.allCases.filter { $0 != .lyrics || settings.showLyrics }, id: \.self) { entry in
                                Text(entry.label).tag(entry)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 12)
                        switch tab {
                        case .queue: QueueList(state: state)
                        case .lyrics: LyricsPanel(song: current)
                        case .injekt: InjektPanel(state: state)
                        }
                    }
                    .padding(.bottom, 32)
                }
                .coordinateSpace(name: "player")
                // Once the pull has started the list stops scrolling, so the whole
                // card moves with your finger instead of the list sliding inside it.
                .scrollDisabled(pulling)
                .onPreferenceChange(TopOffsetKey.self) { topOffset = $0 }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 15)
                        .onChanged { value in
                            if !pulling {
                                // Only a downward pull that starts with the list at its top.
                                guard value.translation.height > 0, abs(value.translation.height) > abs(value.translation.width), topOffset >= -2 else { return }
                                pulling = true
                            }
                            pull = max(0, value.translation.height)
                        }
                        .onEnded { value in
                            guard pulling else { return }
                            pulling = false
                            if pull > 140 || value.predictedEndTranslation.height > 420 {
                                close()
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { pull = 0 }
                            }
                        }
                )
                .task(id: "\(song.id):\(graph.library.version)") {
                    live = await graph.library.song(song.id)
                }
            } else {
                VStack {
                    HStack {
                        IconButton(icon: "chevron.down", label: "Close player", action: close)
                        Spacer()
                    }
                    Spacer()
                    Text("Nothing is playing.").foregroundStyle(theme.colors.ink2)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { ArtworkBackdrop(coverId: state.current?.artworkId) }
        // Pulled down, the player is a card: rounded like the screen, with a
        // shadow, over the dimmed app behind it.
        .mask {
            RoundedRectangle(cornerRadius: pull > 0 ? Self.cardRadius : 0, style: .continuous)
                .ignoresSafeArea()
        }
        .shadow(color: .black.opacity(pull > 0 ? 0.35 : 0), radius: 24, y: -4)
        .scaleEffect(1 - min(1, pull / 900) * 0.08, anchor: .top)
        .offset(y: pull)
        .background {
            Color.black
                .opacity(0.35 * (1 - min(1, pull / 500)))
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    #if DEBUG
    private static var initialPull: CGFloat { ProcessInfo.processInfo.environment["KULTR_SCREEN"] == "pull" ? 220 : 0 }
    #else
    private static let initialPull: CGFloat = 0
    #endif

    /** About the corner radius of a modern iPhone's screen. */
    private static let cardRadius: CGFloat = 44

    private func close() {
        // The pull is kept, so the card carries on down from where you let go.
        AppGraph.shared.actions.closePlayer()
    }

    @ViewBuilder
    private func header(_ current: Song, state: PlayerUiState, settings: Settings) -> some View {
        let graph = AppGraph.shared
        let c = theme.colors
        VStack(spacing: 0) {
            SwipeArtwork(song: current)
                .padding(.top, 8)
            Text(current.title)
                .font(KFont.headlineSmall)
                .foregroundStyle(c.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
            HStack(spacing: 0) {
                Button {
                    close()
                    graph.actions.openArtist(current.artistId)
                } label: {
                    Text(current.artist ?? "").font(KFont.bodyLarge).foregroundStyle(c.ink2).lineLimit(1)
                }
                .buttonStyle(PressableStyle())
                .disabled(current.artistId == nil)
                if let album = current.album, !album.isEmpty, !current.isRadio {
                    Text(" — ").foregroundStyle(c.ink3)
                    Button {
                        close()
                        graph.actions.openAlbum(current.albumId)
                    } label: {
                        Text(album).font(KFont.bodyLarge).foregroundStyle(c.ink2).lineLimit(1)
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(current.albumId == nil)
                }
            }
            .padding(.top, 4)
            HStack(spacing: 6) {
                if let year = current.year { Tag("\(year)") }
                if let genre = current.genre {
                    Tag(genre) {
                        close()
                        graph.actions.openGenre(genre)
                    }
                }
                if let suffix = current.suffix { Tag(suffix.uppercased()) }
                if let bitRate = current.bitRate { Tag("\(bitRate) kbps") }
                if let rating = current.userRating, rating > 0 { Tag("\(rating) ★") { graph.actions.rate(current) } }
            }
            .padding(.top, 10)
            let plan = graph.player.transition.fromSongId == current.id ? graph.player.transition.upcoming : nil
            PositionReader { position in
                Scrubber(
                    positionMs: position,
                    durationMs: state.durationMs,
                    onSeek: { graph.player.seekTo($0) },
                    style: settings.playhead,
                    plan: plan,
                    countDown: settings.timeRemaining,
                    onToggleCountDown: { graph.settings.update { $0.timeRemaining.toggle() } },
                    reduceMotion: settings.reduceMotion
                )
            }
            .padding(.top, 16)
            Transport(state: state, song: current)
        }
        .padding(.horizontal, 20)
    }
}

private struct PlayerTopBar: View {
    @Environment(\.kultr) private var theme
    let song: Song
    let onClose: () -> Void

    var body: some View {
        let graph = AppGraph.shared
        let injektOn = theme.settings.injektEnabled
        let downloaded = graph.offline.downloadedIds.contains(song.id)
        VStack(spacing: 6) {
            // The grabber says "pull me down", as on any sheet.
            Capsule()
                .fill(theme.colors.ink3.opacity(0.6))
                .frame(width: 38, height: 5)
                .padding(.top, 6)
                .accessibilityHidden(true)
        HStack(spacing: 8) {
            GlassIconButton(icon: "chevron.down", size: 40, label: "Close player", action: onClose)
            Eyebrow(song.isRadio ? "Internet radio" : (song.album ?? "Now playing"))
                .frame(maxWidth: .infinity, alignment: .leading)
            // Lit while InjeKt plans the transitions; tap to switch it off and on.
            Pill("InjeKt", icon: "sparkles", accent: injektOn) {
                graph.settings.update { $0.injektEnabled.toggle() }
            }
            .accessibilityValue(injektOn ? "On" : "Off")
            CastButton(tint: theme.colors.ink)
            Menu {
                Button { graph.ui.sleepTimer = true } label: { Label("Sleep timer…", systemImage: "moon.fill") }
                if !song.isRadio {
                    Button { graph.actions.addToPlaylist([song]) } label: { Label("Add to playlist…", systemImage: "text.badge.plus") }
                    Button { graph.actions.rate(song) } label: { Label("Rate…", systemImage: "star.fill") }
                    if song.albumId != nil {
                        Button { onClose(); graph.actions.openAlbum(song.albumId) } label: { Label("Go to album", systemImage: "opticaldisc") }
                    }
                    if song.artistId != nil {
                        Button { onClose(); graph.actions.openArtist(song.artistId) } label: { Label("Go to artist", systemImage: "person.fill") }
                    }
                    if !downloaded {
                        Button { graph.actions.download([song], song.title) } label: { Label("Download", systemImage: "arrow.down.circle") }
                    }
                }
                Button(role: .destructive) {
                    graph.player.stop()
                    onClose()
                } label: { Label("Stop and clear queue", systemImage: "xmark") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.colors.ink)
                    .frame(width: 40, height: 40)
                    .kultrGlass(Circle(), interactive: true, shadow: false)
            }
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 12)
        }
    }
}

/** The big artwork; swipe it sideways to skip. */
private struct SwipeArtwork: View {
    @Environment(\.kultr) private var theme
    let song: Song
    @State private var drag: CGFloat = 0

    var body: some View {
        ArtworkFill(coverId: song.artworkId, radius: theme.radii.xl, label: song.isRadio ? song.title : nil, pixels: 800)
            .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
            .padding(.horizontal, 12)
            .offset(x: drag)
            .rotationEffect(.degrees(Double(drag) / 60))
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        if abs(value.translation.width) > abs(value.translation.height) { drag = value.translation.width }
                    }
                    .onEnded { _ in
                        let player = AppGraph.shared.player
                        if drag > 90 { player.previous() } else if drag < -90 { player.next() }
                        withAnimation(.spring()) { drag = 0 }
                    }
            )
            .onChange(of: song.id) { _, _ in drag = 0 }
    }
}

private struct Transport: View {
    @Environment(\.kultr) private var theme
    let state: PlayerUiState
    let song: Song

    var body: some View {
        let graph = AppGraph.shared
        let player = graph.player
        let c = theme.colors
        VStack(spacing: 0) {
            HStack {
                IconButton(icon: "shuffle", tint: state.shuffle ? c.accent : c.ink2, label: "Shuffle") { player.setShuffle(!state.shuffle) }
                Spacer()
                IconButton(icon: "backward.end.fill", size: 30, label: "Previous") { player.previous() }
                Spacer()
                Button {
                    Haptics.tap()
                    player.toggle()
                } label: {
                    ZStack {
                        if state.buffering && state.playWhenReady {
                            ProgressView().tint(c.ink).controlSize(.large)
                        } else {
                            Image(systemName: state.playWhenReady && !state.ended ? "pause.fill" : "play.fill")
                                .font(.system(size: 46, weight: .bold))
                                .foregroundStyle(c.ink)
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .frame(width: 84, height: 84)
                    .contentShape(Circle())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(state.playWhenReady ? "Pause" : "Play")
                Spacer()
                IconButton(icon: "forward.end.fill", size: 30, label: "Next") { player.next() }
                Spacer()
                IconButton(
                    icon: state.repeatMode == .one ? "repeat.1" : "repeat",
                    tint: state.repeatMode != .off ? c.accent : c.ink2,
                    label: "Repeat"
                ) { player.cycleRepeat() }
            }
            .padding(.top, 4)
            HStack {
                if !song.isRadio {
                    IconButton(
                        icon: song.isStarred ? "heart.fill" : "heart",
                        tint: song.isStarred ? c.accent : c.ink2,
                        label: song.isStarred ? "Remove from favourites" : "Add to favourites"
                    ) { graph.actions.setFavourite(song, !song.isStarred) }
                }
                IconButton(icon: "moon.fill", tint: player.sleepTimer != nil ? c.accent : c.ink2, label: "Sleep timer") {
                    graph.ui.sleepTimer = true
                }
            }
        }
    }
}

// ------------------------------------------------------------------ queue --

private struct QueueList: View {
    @Environment(\.kultr) private var theme
    let state: PlayerUiState

    var body: some View {
        let upNext = state.upNext
        LazyVStack(spacing: 0) {
            HStack {
                Text(upNext.isEmpty ? "Nothing queued after this track." : "\(upNext.count) up next")
                    .font(KFont.bodyMedium)
                    .foregroundStyle(theme.colors.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !upNext.isEmpty {
                    IconButton(icon: "trash", tint: theme.colors.ink2, size: 18, label: "Clear up next") {
                        AppGraph.shared.player.clearUpcoming()
                    }
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            ForEach(upNext) { entry in
                QueueRow(index: entry.index, song: entry.song, size: state.queue.count, currentIndex: state.index)
            }
        }
    }
}

private struct QueueRow: View {
    @Environment(\.kultr) private var theme
    let index: Int
    let song: Song
    let size: Int
    let currentIndex: Int
    @State private var drag: CGFloat = 0

    private static let rowHeight: CGFloat = 64

    var body: some View {
        let player = AppGraph.shared.player
        let c = theme.colors
        HStack(spacing: 0) {
            Artwork(coverId: song.artworkId, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(KFont.bodyLarge.weight(.medium)).foregroundStyle(c.ink).lineLimit(1)
                Text(song.artist ?? "").font(KFont.bodySmall).foregroundStyle(c.ink3).lineLimit(1)
            }
            .padding(.leading, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let duration = song.duration {
                Text(Format.time(Double(duration))).font(.system(size: 12).monospacedDigit()).foregroundStyle(c.ink3)
            }
            Menu {
                Button("Play now") { player.jumpTo(index) }
                Button("Remove from queue", role: .destructive) { player.remove(index) }
                Button("Move to top") {
                    let target = currentIndex + 1
                    if target >= 0 && target < size { player.move(index, target) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(c.ink3)
                    .frame(width: 40, height: 44)
            }
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(c.ink3)
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag = $0.translation.height }
                        .onEnded { _ in
                            let steps = Int((drag / Self.rowHeight).rounded())
                            let target = min(max(index + steps, currentIndex + 1), size - 1)
                            drag = 0
                            if target != index { player.move(index, target) }
                        }
                )
                .accessibilityLabel("Drag to reorder")
        }
        .padding(.leading, 20)
        .padding(.trailing, 4)
        .frame(height: Self.rowHeight)
        .background(drag != 0 ? c.elevated : .clear)
        .shadow(color: .black.opacity(drag != 0 ? 0.3 : 0), radius: 8)
        .offset(y: drag)
        .zIndex(drag != 0 ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture { player.jumpTo(index) }
    }
}

// ----------------------------------------------------------------- lyrics --

private struct LyricsPanel: View {
    @Environment(\.kultr) private var theme
    let song: Song
    @State private var doc: LyricsDoc?
    @State private var loading = true

    var body: some View {
        let c = theme.colors
        GlassPanel {
            if loading {
                Text("Looking for lyrics…").foregroundStyle(c.ink3)
            } else if let doc, !doc.lines.isEmpty {
                PositionReader { position in
                    let active = doc.activeIndex(Double(position) / 1000)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(doc.lines.enumerated()), id: \.offset) { i, line in
                            let isActive = i == active
                            Text(line.text.trimmingCharacters(in: .whitespaces).isEmpty ? "♪" : line.text)
                                .font(.system(size: isActive ? 22 : 18, weight: isActive ? .bold : .medium))
                                .foregroundStyle(!doc.synced ? c.ink : (isActive ? c.accent : (i < active ? c.ink3 : c.ink2)))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if doc.synced, let start = line.start { AppGraph.shared.player.seekTo(Int64(start * 1000)) }
                                }
                        }
                    }
                    .animation(.easeOut(duration: 0.2), value: active)
                }
            } else {
                Text("No lyrics for this track.").foregroundStyle(c.ink3)
            }
        }
        .padding(.horizontal, 16)
        .task(id: song.id) {
            loading = true
            doc = try? await AppGraph.shared.library.lyrics(song)
            loading = false
        }
    }
}

// ----------------------------------------------------------------- injekt --

private struct InjektPanel: View {
    @Environment(\.kultr) private var theme
    let state: PlayerUiState
    @State private var currentAnalysis: TrackAnalysis?
    @State private var nextAnalysis: TrackAnalysis?
    @State private var analysing = false

    var body: some View {
        let graph = AppGraph.shared
        let c = theme.colors
        let transition = graph.player.transition
        if let current = state.current {
            let next: Song? = state.index + 1 < state.queue.count ? state.queue[state.index + 1].song : nil
            VStack(spacing: 12) {
                GlassPanel {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow("The next transition")
                        let plan = transition.active ?? (transition.fromSongId == current.id ? transition.upcoming : nil)
                        if !theme.settings.injektEnabled {
                            Text("InjeKt is off, so tracks are handed over with a plain crossfade.").foregroundStyle(c.ink2)
                        } else if let plan {
                            Text(plan.label).font(KFont.titleMedium).foregroundStyle(c.accent)
                            Text(plan.reason).font(KFont.bodyMedium).foregroundStyle(c.ink2)
                            Text(
                                "Starts at \(Format.time(plan.startAt)) · lasts \(String(format: "%.1f", plan.duration))s" +
                                    (plan.inStartOffset > 1 ? " · next track enters at \(Format.time(plan.inStartOffset))" : "")
                            )
                            .font(KFont.bodySmall)
                            .foregroundStyle(c.ink3)
                        } else {
                            Text(next == nil ? "Nothing is queued after this track." : "Planned about 35 seconds before the end of the track.")
                                .foregroundStyle(c.ink2)
                        }
                    }
                }
                AnalysisCard(title: "This track", song: current, analysis: currentAnalysis)
                if let next { AnalysisCard(title: "Up next", song: next, analysis: nextAnalysis) }
                if currentAnalysis == nil || (next != nil && nextAnalysis == nil) {
                    HStack {
                        Pill(analysing ? "Analysing…" : "Analyse now", icon: "sparkles", enabled: !analysing) {
                            analysing = true
                            Task {
                                _ = await graph.analysis.getOrAnalyse(current)
                                if let next { _ = await graph.analysis.getOrAnalyse(next) }
                                analysing = false
                            }
                        }
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 16)
            .task(id: "\(current.id):\(next?.id ?? ""):\(graph.library.analysisVersion)") {
                currentAnalysis = await graph.analysis.cached(current.id)
                if let next {
                    nextAnalysis = await graph.analysis.cached(next.id)
                } else {
                    nextAnalysis = nil
                }
            }
        }
    }
}

private struct AnalysisCard: View {
    @Environment(\.kultr) private var theme
    let title: String
    let song: Song
    let analysis: TrackAnalysis?

    var body: some View {
        let c = theme.colors
        GlassPanel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Artwork(coverId: song.artworkId, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow(title)
                        Text(song.title).font(KFont.bodyLarge.weight(.semibold)).foregroundStyle(c.ink).lineLimit(1)
                    }
                }
                if let analysis {
                    HStack(spacing: 8) {
                        stat("Tempo", String(format: "%.1f", analysis.bpm), analysis.bpmSource == .tag ? "from tag" : "\(Int((analysis.bpmConfidence * 100).rounded()))% sure")
                        stat("Key", analysis.keyName, analysis.camelot)
                        stat("Energy", "\(Int((analysis.energy * 100).rounded()))", "of 100")
                    }
                    Text("Intro ends \(Format.time(analysis.introEnd)) · outro from \(Format.time(analysis.outroStart))")
                        .font(KFont.bodySmall)
                        .foregroundStyle(c.ink3)
                } else {
                    Text("Not analysed yet.").font(KFont.bodySmall).foregroundStyle(c.ink3)
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ note: String) -> some View {
        let c = theme.colors
        let shape = RoundedRectangle(cornerRadius: theme.radii.sm, style: .continuous)
        return VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(c.ink3)
            Text(value).font(.system(size: 20, weight: .bold)).foregroundStyle(c.ink).lineLimit(1).minimumScaleFactor(0.7)
            Text(note).font(.system(size: 11)).foregroundStyle(c.ink3).lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(c.glass))
        .overlay(shape.strokeBorder(c.line, lineWidth: 1))
    }
}
