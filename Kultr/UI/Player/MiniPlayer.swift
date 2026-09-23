import AVKit
import SwiftUI

/** The playback position, polled while on screen. */
struct PositionReader<Content: View>: View {
    var interval: Double = 0.2
    @ViewBuilder let content: (Int64) -> Content
    @State private var position: Int64 = 0

    var body: some View {
        content(position)
            .task {
                while !Task.isCancelled {
                    position = AppGraph.shared.player.positionMs()
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                }
            }
    }
}

/** "Play on another device": AirPlay speakers, Apple TVs and HomePods. */
struct CastButton: View {
    @Environment(\.kultr) private var theme
    var tint: Color?

    var body: some View {
        RoutePicker(tint: UIColor(tint ?? theme.colors.ink2), active: UIColor(theme.colors.accent))
            .frame(width: 44, height: 44)
            .accessibilityLabel("Play on another device")
    }
}

private struct RoutePicker: UIViewRepresentable {
    let tint: UIColor
    let active: UIColor

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.tintColor = tint
        view.activeTintColor = active
    }
}

/**
 * The strip above the tab bar: what is playing, previous, play/pause and
 * next. Swipe it left for the next track and right for the previous one.
 */
struct MiniPlayer: View {
    @Environment(\.kultr) private var theme
    @State private var swipe: CGFloat = 0
    @State private var liveStarred: Bool?

    var body: some View {
        let graph = AppGraph.shared
        let state = graph.player.state
        if let song = state.current {
            let c = theme.colors
            let starred = liveStarred ?? song.isStarred
            let shape = RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Artwork(coverId: song.artworkId, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title)
                            .font(KFont.bodyLarge.weight(.semibold))
                            .foregroundStyle(c.ink)
                            .lineLimit(1)
                        Text(song.artist ?? "")
                            .font(KFont.bodySmall)
                            .foregroundStyle(c.ink3)
                            .lineLimit(1)
                    }
                    .padding(.leading, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !song.isRadio {
                        IconButton(icon: starred ? "heart.fill" : "heart", tint: starred ? c.accent : c.ink2, size: 18, label: starred ? "Remove from favourites" : "Add to favourites") {
                            liveStarred = !starred
                            graph.actions.setFavourite(song, !starred)
                        }
                    }
                    IconButton(icon: "backward.end.fill", size: 18, label: "Previous") { graph.player.previous() }
                    IconButton(icon: state.playWhenReady && !state.ended ? "pause.fill" : "play.fill", size: 22, label: state.playWhenReady ? "Pause" : "Play") {
                        graph.player.toggle()
                    }
                    IconButton(icon: "forward.end.fill", size: 18, label: "Next") { graph.player.next() }
                }
                .padding(8)
                .offset(x: swipe)
                .opacity(1 - min(0.7, abs(swipe) / 300))
                PositionReader(interval: 0.5) { position in
                    GeometryReader { proxy in
                        let fraction = state.durationMs > 0 ? min(1, max(0, Double(position) / Double(state.durationMs))) : 0
                        ZStack(alignment: .leading) {
                            Rectangle().fill(c.ink4)
                            Rectangle().fill(c.accent).frame(width: proxy.size.width * fraction)
                        }
                    }
                    .frame(height: 2)
                }
            }
            .background(shape.fill(c.elevated.opacity(0.94)))
            .background(shape.fill(c.accent.opacity(0.10)))
            .overlay(shape.strokeBorder(c.edge, lineWidth: 1))
            .clipShape(shape)
            .contentShape(shape)
            .onTapGesture { graph.actions.openPlayer() }
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        if abs(value.translation.width) > abs(value.translation.height) { swipe = value.translation.width }
                    }
                    .onEnded { value in
                        let travelled = value.translation.width
                        guard abs(travelled) >= 72 else {
                            withAnimation(.spring()) { swipe = 0 }
                            return
                        }
                        // Slide out the way the finger went, change track, then
                        // bring the new one in from the other side.
                        let direction: CGFloat = travelled < 0 ? -1 : 1
                        withAnimation(.easeIn(duration: 0.14)) { swipe = direction * 400 }
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 140_000_000)
                            if direction < 0 { graph.player.next() } else { graph.player.previous() }
                            swipe = -direction * 200
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { swipe = 0 }
                        }
                    }
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .onChange(of: song.id) { _, _ in liveStarred = nil }
            .task(id: "\(song.id):\(graph.library.version)") {
                if let live = await graph.library.song(song.id) { liveStarred = live.isStarred }
            }
        }
    }
}
