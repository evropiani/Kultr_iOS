import SwiftUI
import UIKit

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

/**
 * The full player. It opens as a sheet, so pulling it down (from the top of
 * its list) is iOS's own gesture: the system moves it, at the screen's full
 * frame rate, and nothing in here is redrawn while it moves.
 */
struct NowPlayingScreen: View {
    @Environment(\.kultr) private var theme
    @State private var tab: PlayerTab = .queue
    @State private var live: Song?

    var body: some View {
        let graph = AppGraph.shared
        let state = graph.player.state
        let settings = theme.settings
        ZStack {
            if let song = state.current {
                let current = live?.id == song.id ? live! : song
                ScrollViewReader { scroller in
                    ScrollView {
                        VStack(spacing: 0) {
                            PlayerTopBar(song: current, onClose: close)
                            header(current, state: state, settings: settings) { shown in
                                // Swiping up the cover: open that panel and scroll it into view.
                                withAnimation(theme.ease) {
                                    tab = shown == .lyrics && !settings.showLyrics ? .queue : shown
                                    scroller.scrollTo("panels", anchor: .top)
                                }
                            }
                            Picker("Show", selection: Binding(get: { tab }, set: { value in withAnimation(theme.ease) { tab = value } })) {
                                ForEach(PlayerTab.allCases.filter { $0 != .lyrics || settings.showLyrics }, id: \.self) { entry in
                                    Text(entry.label).tag(entry)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 12)
                            .id("panels")
                            switch tab {
                            case .queue: QueueList(state: state)
                            case .lyrics: LyricsPanel(song: current)
                            case .injekt: InjektPanel(state: state)
                            }
                        }
                        .padding(.bottom, 32)
                    }
                }
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
    }

    private func close() {
        AppGraph.shared.actions.closePlayer()
    }

    @ViewBuilder
    private func header(_ current: Song, state: PlayerUiState, settings: Settings, show: @escaping (PlayerTab) -> Void) -> some View {
        let graph = AppGraph.shared
        let c = theme.colors
        VStack(spacing: 0) {
            SwipeArtwork(song: current, show: show)
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
            SongFacts(song: current, close: close)
                .padding(.top, 8)
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
                    reduceMotion: settings.reduceMotion,
                    songId: current.isRadio ? nil : current.id
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
                    if !downloaded && !LocalLibrary.isLocal(song) {
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
                    .kultrGlass(Circle(), interactive: true)
            }
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 12)
        // Below the sheet's own grabber.
        .padding(.top, 16)
    }
}

/** Year, genre, format and rating in one quiet line; the genre and the rating can be tapped. */
private struct SongFacts: View {
    @Environment(\.kultr) private var theme
    let song: Song
    let close: () -> Void

    private struct Fact {
        let text: String
        var action: (() -> Void)?
    }

    private var facts: [Fact] {
        let graph = AppGraph.shared
        var out: [Fact] = []
        if let year = song.year { out.append(Fact(text: String(year))) }
        if let genre = song.genre {
            out.append(Fact(text: genre, action: {
                close()
                graph.actions.openGenre(genre)
            }))
        }
        if let suffix = song.suffix { out.append(Fact(text: suffix.uppercased())) }
        if let bitRate = song.bitRate { out.append(Fact(text: "\(bitRate) kbps")) }
        if let rating = song.userRating, rating > 0 { out.append(Fact(text: "\(rating) ★", action: { graph.actions.rate(song) })) }
        return out
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                if index > 0 { Text("·") }
                if let action = fact.action {
                    Button(fact.text, action: action).buttonStyle(PressableStyle())
                } else {
                    Text(fact.text)
                }
            }
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(theme.colors.ink3)
        .lineLimit(1)
    }
}

/**
 * The big artwork. Swipe it sideways to skip; double-tap, hold and swipe up do
 * what Settings > Playback > The cover says (by default: heart the track, mix
 * into the next one, show the queue).
 */
private struct SwipeArtwork: View {
    @Environment(\.kultr) private var theme
    let song: Song
    /** Opens a panel under the player and scrolls to it. */
    let show: (PlayerTab) -> Void
    @State private var drag: CGFloat = 0
    /** The symbol that pops up over the cover after a gesture, briefly. */
    @State private var flash: String?
    @State private var flashId = 0

    var body: some View {
        let settings = theme.settings
        ArtworkFill(coverId: song.artworkId, radius: theme.radii.xl, label: song.isRadio ? song.title : nil, pixels: 800)
            .overlay {
                if let flash {
                    Image(systemName: flash)
                        .font(.system(size: 88, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 12)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                        .id(flashId)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
            .padding(.horizontal, 12)
            .offset(x: drag)
            .rotationEffect(.degrees(Double(drag) / 60))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { perform(settings.coverDoubleTap) }
            .onLongPressGesture(minimumDuration: 0.45) { perform(settings.coverHold) }
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        if abs(value.translation.width) > abs(value.translation.height) { drag = value.translation.width }
                    }
                    .onEnded { value in
                        let player = AppGraph.shared.player
                        let up = -value.translation.height
                        if drag > 90 {
                            player.previous()
                        } else if drag < -90 {
                            player.next()
                        } else if up > 60, up > abs(value.translation.width) * 1.5 {
                            perform(settings.coverSwipeUp)
                        }
                        withAnimation(.spring()) { drag = 0 }
                    }
            )
            .onChange(of: song.id) { _, _ in drag = 0 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Cover of \(song.album ?? song.title)")
            .accessibilityAction(named: "Next track") { AppGraph.shared.player.next() }
            .accessibilityAction(named: "Previous track") { AppGraph.shared.player.previous() }
            .modifier(CoverAccessibility(actions: [settings.coverDoubleTap, settings.coverHold, settings.coverSwipeUp], perform: perform))
    }

    private func perform(_ action: CoverAction) {
        let graph = AppGraph.shared
        switch action {
        case .none:
            return
        case .favourite:
            guard !song.isRadio else { return }
            let starred = graph.ui.isStarred(song)
            graph.actions.setFavourite(song, !starred)
            pop(starred ? "heart.slash.fill" : "heart.fill")
        case .queue:
            show(.queue)
        case .lyrics:
            show(.lyrics)
        case .mixNow:
            if graph.player.mixNow() {
                Haptics.tap()
                pop("arrow.triangle.merge")
                graph.messages.show("Mixing into the next track")
            } else {
                graph.messages.show("Nothing to mix into: this is the last track")
            }
        case .playPause:
            Haptics.tap()
            let playing = graph.player.state.playWhenReady
            graph.player.toggle()
            pop(playing ? "pause.fill" : "play.fill")
        case .addToPlaylist:
            guard !song.isRadio else { return }
            graph.actions.addToPlaylist([song])
        }
    }

    private func pop(_ symbol: String) {
        flashId += 1
        let id = flashId
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { flash = symbol }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            if flashId == id { withAnimation(.easeOut(duration: 0.25)) { flash = nil } }
        }
    }
}

/** The cover's gestures as VoiceOver actions, without the ones switched off or doubled. */
private struct CoverAccessibility: ViewModifier {
    let actions: [CoverAction]
    let perform: (CoverAction) -> Void

    func body(content: Content) -> some View {
        var seen = Set<CoverAction>()
        let unique = actions.filter { $0 != .none && seen.insert($0).inserted }
        return unique.reduce(AnyView(content)) { view, action in
            AnyView(view.accessibilityAction(named: action.label) { perform(action) })
        }
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
        let mode: ShuffleMode = theme.settings.karousel ? .karousel : (state.shuffle ? .shuffle : .off)
        VStack(spacing: 0) {
            HStack {
                ModeButton(
                    icon: mode == .karousel ? "infinity" : "shuffle",
                    on: mode != .off,
                    label: mode == .karousel ? "Karousel on" : (mode == .shuffle ? "Shuffle on" : "Shuffle off")
                ) {
                    switch player.cycleShuffle() {
                    case .shuffle: graph.messages.show("Shuffle on")
                    case .karousel: graph.messages.show("Karousel on: when the queue runs out, music like it keeps playing")
                    case .off: graph.messages.show("Shuffle and Karousel off")
                    }
                }
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
                    .modifier(BeatPulse(song: song, playing: state.playWhenReady && !state.buffering && !state.ended))
                    .contentShape(Circle())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(state.playWhenReady ? "Pause" : "Play")
                Spacer()
                IconButton(icon: "forward.end.fill", size: 30, label: "Next") { player.next() }
                Spacer()
                ModeButton(
                    icon: state.repeatMode == .one ? "repeat.1" : "repeat",
                    on: state.repeatMode != .off,
                    label: state.repeatMode == .one ? "Repeat this track" : (state.repeatMode == .all ? "Repeat the queue" : "Repeat off")
                ) {
                    if state.repeatMode == .off && mode == .karousel {
                        graph.messages.show("Repeat on: Karousel waits until repeat is off again")
                    }
                    player.cycleRepeat()
                }
            }
            .padding(.top, 4)
            HStack {
                if !song.isRadio {
                    let starred = graph.ui.isStarred(song)
                    IconButton(
                        icon: starred ? "heart.fill" : "heart",
                        tint: starred ? c.accent : c.ink2,
                        label: starred ? "Remove from favourites" : "Add to favourites"
                    ) { graph.actions.setFavourite(song, !starred) }
                }
                IconButton(icon: "moon.fill", tint: player.sleepTimer != nil ? c.accent : c.ink2, label: "Sleep timer") {
                    graph.ui.sleepTimer = true
                }
            }
        }
    }
}

/**
 * Beat pulse: the play button swells a little on each downbeat InjeKt found,
 * with a soft orange ring behind it, and (if switched on) the phone taps
 * along. Only while playing a track with a confident tempo, with the player
 * open and the app in front; never with Reduce motion.
 */
private struct BeatPulse: ViewModifier {
    @Environment(\.kultr) private var theme
    @Environment(\.scenePhase) private var phase
    let song: Song
    let playing: Bool
    @State private var grid: BeatGrid?

    func body(content: Content) -> some View {
        let settings = theme.settings
        let visual = settings.beatPulse && !theme.reduceMotion
        let live = playing && phase == .active && grid != nil
        let graph = AppGraph.shared
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !(live && visual))) { _ in
            let amount = live && visual ? (grid?.pulse(Double(graph.player.positionMs()) / 1000) ?? 0) : 0
            content
                .background {
                    Circle()
                        .fill(theme.colors.accent.opacity(0.22 * amount))
                        .scaleEffect(0.82 + 0.18 * amount)
                }
                .scaleEffect(1 + 0.06 * amount)
        }
        .task(id: "\(song.id):\(graph.analysis.lastAnalysed == song.id)") {
            grid = song.isRadio ? nil : (await graph.analysis.cached(song.id)).flatMap(BeatGrid.init)
        }
        .task(id: "\(live):\(settings.beatHaptics):\(song.id)") {
            guard live, settings.beatHaptics, let grid else { return }
            let tap = UIImpactFeedbackGenerator(style: .soft)
            tap.prepare()
            while !Task.isCancelled {
                let wait = grid.untilDownbeat(Double(graph.player.positionMs()) / 1000)
                try? await Task.sleep(nanoseconds: UInt64(max(0.05, wait) * 1_000_000_000))
                if Task.isCancelled { break }
                // A seek can land anywhere; only tap when this really is a downbeat.
                let since = grid.sinceDownbeat(Double(graph.player.positionMs()) / 1000)
                if since >= 0 && (since < 0.08 || grid.bar - since < 0.08) {
                    tap.impactOccurred(intensity: 0.7)
                }
                try? await Task.sleep(nanoseconds: 120_000_000)
                tap.prepare()
            }
        }
    }
}

/** Shuffle and repeat: tinted, on a disc, while they're on, so it reads at a glance. */
private struct ModeButton: View {
    @Environment(\.kultr) private var theme
    let icon: String
    let on: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        let c = theme.colors
        Button {
            Haptics.select()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(on ? c.accent : c.ink2)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 40, height: 40)
                .background(Circle().fill(on ? c.accent.opacity(0.2) : .clear))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

// ------------------------------------------------------------------ queue --

private struct QueueList: View {
    @Environment(\.kultr) private var theme
    let state: PlayerUiState
    /** The tracks about to be saved as a playlist, while it is being named. */
    @State private var saving: [Song]?
    @State private var name = ""

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM HH:mm")
        return formatter
    }()

    var body: some View {
        let upNext = state.upNext
        let all = state.queue.map(\.song).filter { !$0.isRadio }
        let played = state.index >= 0 ? state.queue.prefix(state.index + 1).map(\.song).filter { !$0.isRadio } : []
        LazyVStack(spacing: 0) {
            HStack {
                Text(upNext.isEmpty ? "Nothing queued after this track." : "\(upNext.count) up next")
                    .font(KFont.bodyMedium)
                    .foregroundStyle(theme.colors.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !all.isEmpty {
                    Menu {
                        Section("Save as a playlist") {
                            if played.count > 1 {
                                Button { save(played) } label: {
                                    Label("What you've played, \(Format.count(played.count, "track"))", systemImage: "clock.arrow.circlepath")
                                }
                            }
                            Button { save(all) } label: {
                                Label("The whole queue, \(Format.count(all.count, "track"))", systemImage: "list.bullet")
                            }
                        }
                    } label: {
                        Image(systemName: "text.badge.plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(theme.colors.ink2)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Save as a playlist")
                }
                if !upNext.isEmpty {
                    IconButton(icon: "trash", tint: theme.colors.ink2, size: 18, label: "Clear up next") {
                        AppGraph.shared.player.clearUpcoming()
                    }
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            // What Karousel added goes under its own heading.
            let firstKarousel = upNext.firstIndex { $0.karousel } ?? upNext.count
            ForEach(upNext[..<firstKarousel]) { entry in
                QueueRow(index: entry.index, song: entry.song, size: state.queue.count, currentIndex: state.index)
            }
            let station = AppGraph.shared.player.station
            if let station {
                KarouselHeading(
                    icon: station.icon,
                    title: station.name,
                    text: "\(station.summary). Tracks that fit, mixed by InjeKt, for as long as you like.",
                    onEnd: {
                        AppGraph.shared.player.endStation()
                        AppGraph.shared.messages.show("Station ended")
                    }
                )
            }
            if firstKarousel < upNext.count {
                if station == nil { KarouselHeading(text: "Music like what's playing, so it never stops.") }
                ForEach(upNext[firstKarousel...]) { entry in
                    QueueRow(index: entry.index, song: entry.song, size: state.queue.count, currentIndex: state.index)
                }
            } else if station == nil && theme.settings.karousel && state.current?.isRadio != true {
                KarouselHeading(text: "On: when the queue runs out, music like it keeps playing.")
            }
        }
        .alert("Save as a playlist", isPresented: Binding(isPresent: $saving)) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Save") { commit() }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text(Format.count(saving?.count ?? 0, "track"))
        }
    }

    private func save(_ songs: [Song]) {
        name = "Session, \(Self.stamp.string(from: Date()))"
        saving = songs
    }

    private func commit() {
        guard let songs = saving else { return }
        let title = name.trimmingCharacters(in: .whitespaces)
        let graph = AppGraph.shared
        saving = nil
        Task {
            if let error = await graph.library.createPlaylist(title, songs) {
                graph.messages.error(error)
            } else {
                graph.messages.show("Saved “\(title)”: \(Format.count(songs.count, "track"))", .success)
            }
        }
    }
}

private struct KarouselHeading: View {
    @Environment(\.kultr) private var theme
    var icon = "infinity"
    var title = "Karousel"
    let text: String
    var onEnd: (() -> Void)?

    var body: some View {
        let c = theme.colors
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(c.accent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(c.accent.opacity(0.24)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(KFont.titleSmall.weight(.semibold))
                    .foregroundStyle(c.ink)
                Text(text)
                    .font(KFont.bodySmall)
                    .foregroundStyle(c.ink3)
            }
            Spacer(minLength: 0)
            if let onEnd {
                Button("End", action: onEnd)
                    .font(KFont.labelLarge)
                    .foregroundStyle(c.accent)
                    .accessibilityLabel("End the station")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .accessibilityElement(children: onEnd == nil ? .combine : .contain)
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(c.glass))
        .overlay(shape.strokeBorder(c.line, lineWidth: 1))
    }
}
