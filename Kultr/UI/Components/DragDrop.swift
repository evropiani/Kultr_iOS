import Observation
import SwiftUI
import UIKit

/**
 * Something being dragged: what to call it, a cover to show under the
 * finger, and how to get its tracks. [resolve] is only called on drop, so
 * dragging an album does not load its track list until it is needed.
 */
struct DragPayload {
    let label: String
    let coverId: String?
    let resolve: @MainActor () async -> [Song]
}

/**
 * Where a drag can end, ordered the way the web client orders them:
 * queueing is the common case, deleting is furthest from the finger's path.
 */
enum DropAction: CaseIterable, Hashable {
    case playNext, queue, favourite, download, remove

    var label: String {
        switch self {
        case .playNext: return "Play next"
        case .queue: return "Add to queue"
        case .favourite: return "Favourite"
        case .download: return "Sync offline"
        case .remove: return "Delete downloads"
        }
    }

    var hint: String {
        switch self {
        case .playNext: return "Jump the queue"
        case .queue: return "Play after everything else"
        case .favourite: return "Star on your server"
        case .download: return "Download for offline play"
        case .remove: return "Remove the local copies"
        }
    }

    var icon: String {
        switch self {
        case .playNext: return "play.fill"
        case .queue: return "music.note.list"
        case .favourite: return "heart.fill"
        case .download: return "arrow.down.circle.fill"
        case .remove: return "trash.fill"
        }
    }
}

/** The drag in progress, shared by every drag source and the drop zone. */
@MainActor
@Observable
final class DragDropState {
    private(set) var payload: DragPayload?
    /** Finger position in global coordinates. */
    private(set) var pointer: CGPoint = .zero
    private(set) var hovered: DropAction?
    @ObservationIgnored private var targets: [DropAction: CGRect] = [:]

    func start(_ payload: DragPayload, at point: CGPoint) {
        self.payload = payload
        pointer = point
        hovered = nil
    }

    func move(to point: CGPoint) {
        guard payload != nil else { return }
        pointer = point
        let over = targets.first { $0.value.contains(point) }?.key
        if over != hovered {
            if over != nil { UISelectionFeedbackGenerator().selectionChanged() }
            hovered = over
        }
    }

    /** Finish the drag; true when it was dropped on a target. */
    func finish() -> Bool {
        let dragged = payload
        let target = hovered
        cancel()
        if let dragged, let target {
            AppGraph.shared.actions.drop(dragged, target)
            return true
        }
        return false
    }

    func cancel() {
        withAnimation(.easeOut(duration: 0.2)) {
            payload = nil
            hovered = nil
        }
    }

    func register(_ action: DropAction, _ frame: CGRect) {
        targets[action] = frame
    }
}

/**
 * Long-press and drag this view onto the drop zone. A long press that is
 * released without moving calls [onLongPress] instead, so long-press to
 * select keeps working.
 */
private struct DragSourceModifier: ViewModifier {
    let payload: () -> DragPayload?
    let onLongPress: (() -> Void)?
    @State private var started = false
    @State private var travelled: CGFloat = 0

    func body(content: Content) -> some View {
        content.gesture(
            LongPressGesture(minimumDuration: 0.45)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                .onChanged { value in
                    guard case .second(true, let drag) = value, let drag else { return }
                    let state = AppGraph.shared.ui.drag
                    if !started {
                        started = true
                        travelled = 0
                        if let dragged = payload() {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.easeOut(duration: 0.2)) { state.start(dragged, at: drag.location) }
                        }
                    }
                    travelled = max(travelled, hypot(drag.translation.width, drag.translation.height))
                    state.move(to: drag.location)
                }
                .onEnded { _ in
                    let state = AppGraph.shared.ui.drag
                    let dropped = started && state.finish()
                    if !started {
                        // The press ended before the drag began.
                        onLongPress?()
                    } else if !dropped && travelled < 10 {
                        onLongPress?()
                    }
                    started = false
                    travelled = 0
                }
        )
    }
}

extension View {
    func dragSource(_ payload: @escaping () -> DragPayload?, onLongPress: (() -> Void)? = nil) -> some View {
        modifier(DragSourceModifier(payload: payload, onLongPress: onLongPress))
    }
}

/**
 * The drop targets along the bottom of the screen and the card that follows
 * the finger. Only shown while something is being dragged.
 */
struct DropZoneOverlay: View {
    @Environment(\.kultr) private var theme

    var body: some View {
        let state = AppGraph.shared.ui.drag
        let c = theme.colors
        ZStack(alignment: .bottom) {
            if let payload = state.payload {
                // Dim everything behind, so the targets and their labels stand out.
                Color.black.opacity(c.dark ? 0.6 : 0.4)
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack(spacing: 10) {
                    Text("Drop “\(payload.label)” on…")
                        .font(KFont.labelMedium.weight(.semibold))
                        .foregroundStyle(c.ink)
                        .lineLimit(1)
                    // Three on top, two below: big enough to hit with a thumb.
                    HStack(spacing: 8) {
                        ForEach([DropAction.playNext, .queue, .favourite], id: \.self) { DropTarget(action: $0) }
                    }
                    HStack(spacing: 8) {
                        ForEach([DropAction.download, .remove], id: \.self) { DropTarget(action: $0) }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 40)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: c.background.opacity(0.96), location: 0.2),
                            .init(color: c.background, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))

                GeometryReader { proxy in
                    let origin = proxy.frame(in: .global).origin
                    HStack(spacing: 8) {
                        Artwork(coverId: payload.coverId, size: 36, label: payload.label)
                        Text(payload.label)
                            .font(KFont.bodyMedium.weight(.semibold))
                            .foregroundStyle(c.ink)
                            .lineLimit(1)
                            .padding(.trailing, 6)
                    }
                    .padding(6)
                    .frame(maxWidth: 240, alignment: .leading)
                    .fixedSize()
                    .background(RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous).fill(c.elevated))
                    .overlay(RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous).strokeBorder(c.accent.opacity(0.6), lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                    .position(x: state.pointer.x - origin.x + 90, y: state.pointer.y - origin.y - 60)
                }
                .ignoresSafeArea()
            }
        }
        .allowsHitTesting(false)
    }
}

private struct DropTarget: View {
    @Environment(\.kultr) private var theme
    let action: DropAction

    var body: some View {
        let state = AppGraph.shared.ui.drag
        let c = theme.colors
        let over = state.hovered == action
        let danger = action == .remove
        let tint: Color = over ? (danger ? c.danger : c.accent) : c.ink
        let shape = RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous)
        VStack(spacing: 2) {
            Image(systemName: action.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(height: 24)
            Text(action.label)
                .font(KFont.labelLarge)
                .foregroundStyle(c.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(action.hint)
                .font(KFont.labelSmall)
                .foregroundStyle(c.ink2)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(maxWidth: 160)
        .frame(maxWidth: .infinity)
        .background(shape.fill(c.elevated))
        .background(shape.fill(over ? (danger ? c.danger.opacity(0.16) : c.accentSoft) : .clear))
        .overlay(shape.strokeBorder(over ? tint.opacity(0.8) : c.edge, lineWidth: 1))
        .scaleEffect(over ? 1.06 : 1)
        .offset(y: over ? -6 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: over)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { state.register(action, proxy.frame(in: .global)) }
                    .onChange(of: proxy.frame(in: .global)) { _, frame in state.register(action, frame) }
            }
        )
    }
}
