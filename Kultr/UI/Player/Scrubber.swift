import SwiftUI

/**
 * The progress bar. Drag or tap to seek. When a transition has been planned,
 * the stretch where the next track will come in is hatched, so you can see
 * where the blend starts.
 */
struct Scrubber: View {
    @Environment(\.kultr) private var theme
    @Environment(\.scenePhase) private var phase
    let positionMs: Int64
    let durationMs: Int64
    let onSeek: (Int64) -> Void
    var style: PlayheadStyle = .minimal
    var plan: TransitionPlan?
    var countDown = false
    var onToggleCountDown: () -> Void = {}
    var reduceMotion = false
    /** The track, so the lens can show its beats once InjeKt knows them. */
    var songId: String?

    @State private var dragFraction: Double?
    @State private var grid: BeatGrid?

    var body: some View {
        let c = theme.colors
        let fraction = dragFraction ?? (durationMs > 0 ? min(1, max(0, Double(positionMs) / Double(durationMs))) : 0)
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let width = proxy.size.width
                // The moving playhead is drawn 30 times a second, and only while it can be seen.
                TimelineView(.animation(minimumInterval: reduceMotion ? 1000 : 1.0 / 30, paused: reduceMotion || phase != .active)) { timeline in
                    let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                    Canvas { context, size in
                        draw(context, size, fraction: fraction, phase: phase, colors: c)
                    }
                }
                .contentShape(Rectangle())
                .overlay(alignment: .topLeading) {
                    // The lens: while you drag, the time and the beats under your finger, magnified.
                    if let dragFraction, durationMs > 0 {
                        let lensWidth: CGFloat = 148
                        ScrubLens(ms: Int64(dragFraction * Double(durationMs)), grid: grid, plan: plan)
                            .frame(width: lensWidth)
                            .offset(x: min(max(0, dragFraction * width - lensWidth / 2), max(0, width - lensWidth)), y: -84)
                            .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                            .allowsHitTesting(false)
                    }
                }
                .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: dragFraction == nil)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragFraction = min(1, max(0, value.location.x / max(1, width)))
                        }
                        .onEnded { value in
                            let f = min(1, max(0, value.location.x / max(1, width)))
                            if durationMs > 0 { onSeek(Int64(f * Double(durationMs))) }
                            dragFraction = nil
                        }
                )
            }
            .frame(height: 28)
            .zIndex(1)
            HStack {
                let shownMs = dragFraction.map { Int64($0 * Double(durationMs)) } ?? positionMs
                Text(countDown && durationMs > 0 ? "-" + Format.timeMs(durationMs - shownMs) : Format.timeMs(shownMs))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(c.ink3)
                    .onTapGesture(perform: onToggleCountDown)
                Spacer()
                Text(durationMs > 0 ? Format.timeMs(durationMs) : "--:--")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(c.ink3)
            }
            .padding(.horizontal, 2)
        }
        .task(id: "\(songId ?? ""):\(AppGraph.shared.analysis.lastAnalysed == songId)") {
            grid = await songId.asyncFlatMap { await AppGraph.shared.analysis.cached($0) }.flatMap(BeatGrid.init)
        }
    }

    private func draw(_ context: GraphicsContext, _ size: CGSize, fraction: Double, phase: Double, colors c: KultrColors) {
        let h: CGFloat = 4
        let y = size.height / 2
        let w = size.width
        let track = Path(roundedRect: CGRect(x: 0, y: y - h / 2, width: w, height: h), cornerRadius: h / 2)
        context.fill(track, with: .color(c.ink4))

        // The planned hand-over, hatched.
        if let plan, durationMs > 0, plan.duration > 0.3 {
            let start = min(1, max(0, plan.startAt * 1000 / Double(durationMs)))
            let end = min(1, max(start, (plan.startAt + plan.duration * plan.outgoingRate) * 1000 / Double(durationMs)))
            var x = start * w
            var hatch = Path()
            while x < end * w {
                hatch.move(to: CGPoint(x: x, y: y - h / 2))
                hatch.addLine(to: CGPoint(x: min(x + 2.5, end * w), y: y + h / 2))
                x += 5
            }
            context.stroke(hatch, with: .color(c.accent.opacity(0.55)), lineWidth: 1.5)
        }

        let played = fraction * w
        let playedRect = CGRect(x: 0, y: y - h / 2, width: played, height: h)
        switch style {
        case .wave:
            let gradient = Gradient(colors: [c.accent.opacity(0.5), c.accent, c.accent.opacity(0.5)])
            var local = context
            local.clip(to: Path(roundedRect: playedRect, cornerRadius: h / 2))
            var offset = phase * 120 - 120
            while offset < played {
                local.fill(
                    Path(CGRect(x: offset, y: y - h / 2, width: 120, height: h)),
                    with: .linearGradient(gradient, startPoint: CGPoint(x: offset, y: 0), endPoint: CGPoint(x: offset + 120, y: 0))
                )
                offset += 120
            }
        case .comet:
            context.fill(
                Path(roundedRect: playedRect, cornerRadius: h / 2),
                with: .linearGradient(
                    Gradient(colors: [.clear, c.accent]),
                    startPoint: CGPoint(x: max(0, played - w * 0.35), y: 0),
                    endPoint: CGPoint(x: max(1, played), y: 0)
                )
            )
        case .equalizer:
            let bar: CGFloat = 3
            var x: CGFloat = 0
            var i = 0.0
            while x < played {
                let amp = 0.5 + 0.5 * sin(i * 0.9 + phase * 6.283)
                let bh = h + CGFloat(amp) * 6
                context.fill(
                    Path(roundedRect: CGRect(x: x, y: y - bh / 2, width: min(bar, played - x), height: bh), cornerRadius: bar / 2),
                    with: .color(c.accent)
                )
                x += bar * 1.8
                i += 1
            }
        default:
            context.fill(Path(roundedRect: playedRect, cornerRadius: h / 2), with: .color(c.accent))
        }

        let thumb: CGFloat = dragFraction != nil ? 9 : 6
        let center = CGPoint(x: played, y: y)
        func circle(_ radius: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
        switch style {
        case .glow:
            context.fill(circle(10 + 4 * CGFloat(sin(phase * 6.283))), with: .color(c.accent.opacity(0.25)))
        case .pulse:
            context.fill(circle(thumb + CGFloat(phase) * 14), with: .color(c.accent.opacity((1 - phase) * 0.5)))
        case .comet:
            context.fill(circle(thumb * 2), with: .color(c.accent.opacity(0.35)))
        default:
            break
        }
        context.fill(circle(thumb), with: .color(c.accent))
        context.fill(circle(thumb * 0.35), with: .color(.white.opacity(0.9)))
    }
}

/**
 * The glass lens over the scrubber while it is dragged: the time, large, and
 * eight seconds of the track around it with InjeKt's beats marked, the first
 * beat of each bar taller and orange, and the planned mix shaded.
 */
private struct ScrubLens: View {
    @Environment(\.kultr) private var theme
    let ms: Int64
    let grid: BeatGrid?
    let plan: TransitionPlan?

    private static let span = 8.0

    var body: some View {
        let c = theme.colors
        VStack(spacing: 6) {
            Text(Format.timeMs(ms))
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(c.ink)
            Canvas { context, size in
                let now = Double(ms) / 1000
                let start = now - Self.span / 2
                func x(_ seconds: Double) -> CGFloat { CGFloat((seconds - start) / Self.span) * size.width }
                let mid = size.height / 2
                if let plan, plan.duration > 0.3 {
                    let from = x(plan.startAt), to = x(plan.startAt + plan.duration * plan.outgoingRate)
                    if to > 0 && from < size.width {
                        context.fill(Path(CGRect(x: max(0, from), y: 0, width: min(size.width, to) - max(0, from), height: size.height)), with: .color(c.accent.opacity(0.18)))
                    }
                }
                context.fill(Path(CGRect(x: 0, y: mid - 0.5, width: size.width, height: 1)), with: .color(c.ink3.opacity(0.5)))
                if let grid {
                    let beat = grid.bar / 4
                    var k = Int(((start - grid.offset) / beat).rounded(.up))
                    while true {
                        let time = grid.offset + Double(k) * beat
                        if time > start + Self.span { break }
                        if time >= 0 {
                            let downbeat = ((k % 4) + 4) % 4 == 0
                            let h: CGFloat = downbeat ? size.height : size.height * 0.45
                            context.fill(
                                Path(roundedRect: CGRect(x: x(time) - (downbeat ? 1 : 0.75), y: mid - h / 2, width: downbeat ? 2 : 1.5, height: h), cornerRadius: 1),
                                with: .color(downbeat ? c.accent : c.ink3)
                            )
                        }
                        k += 1
                    }
                } else {
                    // No beats known yet: plain second marks.
                    var second = start.rounded(.up)
                    while second <= start + Self.span {
                        if second >= 0 {
                            context.fill(Path(CGRect(x: x(second) - 0.5, y: mid - 4, width: 1, height: 8)), with: .color(c.ink3))
                        }
                        second += 1
                    }
                }
                // Where your finger is.
                context.fill(Path(roundedRect: CGRect(x: size.width / 2 - 1.5, y: 0, width: 3, height: size.height), cornerRadius: 1.5), with: .color(c.ink))
            }
            .frame(height: 22)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .kultrGlass(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityHidden(true)
    }
}

private extension Optional {
    func asyncFlatMap<T>(_ transform: (Wrapped) async -> T?) async -> T? {
        guard let value = self else { return nil }
        return await transform(value)
    }
}
