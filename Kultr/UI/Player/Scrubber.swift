import SwiftUI

/**
 * The progress bar. Drag or tap to seek. When a transition has been planned,
 * the stretch where the next track will come in is hatched, so you can see
 * where the blend starts.
 */
struct Scrubber: View {
    @Environment(\.kultr) private var theme
    let positionMs: Int64
    let durationMs: Int64
    let onSeek: (Int64) -> Void
    var style: PlayheadStyle = .minimal
    var plan: TransitionPlan?
    var countDown = false
    var onToggleCountDown: () -> Void = {}
    var reduceMotion = false

    @State private var dragFraction: Double?

    var body: some View {
        let c = theme.colors
        let fraction = dragFraction ?? (durationMs > 0 ? min(1, max(0, Double(positionMs) / Double(durationMs))) : 0)
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let width = proxy.size.width
                TimelineView(.animation(minimumInterval: reduceMotion ? 1000 : 1.0 / 30, paused: reduceMotion)) { timeline in
                    let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                    Canvas { context, size in
                        draw(context, size, fraction: fraction, phase: phase, colors: c)
                    }
                }
                .contentShape(Rectangle())
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
