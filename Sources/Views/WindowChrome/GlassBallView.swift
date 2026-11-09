import AppKit
import SwiftUI

struct GlassBallView: View {
    let name: String
    let status: GlassBallStatus
    let reduceMotion: Bool
    let onOpen: () -> Void
    @State private var pulse = false

    private var color: Color {
        switch status {
        case .working: return .blue
        case .attention: return .yellow
        case .finished: return .green
        case .idle: return .gray
        }
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 4) {
                ZStack {
                    Circle().fill(.ultraThinMaterial)
                    Circle().fill(
                        RadialGradient(
                            colors: [.white.opacity(0.65), color.opacity(0.35), color.opacity(0.8)],
                            center: .topLeading, startRadius: 0, endRadius: 68))
                    Circle().strokeBorder(.white.opacity(0.65), lineWidth: 1)
                    Ellipse().fill(.white.opacity(0.5)).frame(width: 24, height: 10).offset(x: -10, y: -18)
                    Image(systemName: status.symbol).font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.primary).shadow(color: .white.opacity(0.5), radius: 2)
                }
                .frame(width: 64, height: 64)
                .shadow(color: color.opacity(pulse ? 0.8 : 0.4), radius: pulse ? 14 : 7)
                .scaleEffect(pulse ? 1.04 : 1)
                Text(name).font(.caption).lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, 5).background(.regularMaterial, in: Capsule())
            }
            .frame(width: GlassBallStatus.compactSize.width, height: GlassBallStatus.compactSize.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(name) · \(status.label). Hover to expand; select to keep open while focused.")
        .accessibilityLabel("\(name), \(status.label)")
        .accessibilityHint("Open subagent mini-window")
        .onAppear { updatePulse() }
        .onChange(of: status) { _, _ in updatePulse() }
        .onChange(of: reduceMotion) { _, _ in updatePulse() }
    }

    private func updatePulse() {
        pulse = false
        if status == .attention && !reduceMotion {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// A passive tracking region; entering never changes keyboard focus or session selection.
struct GlassBallHoverRegion: NSViewRepresentable {
    let paneID: UUID
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> GlassBallHoverView {
        let view = GlassBallHoverView()
        view.paneID = paneID
        view.onHover = onHover
        return view
    }

    func updateNSView(_ view: GlassBallHoverView, context: Context) {
        view.paneID = paneID
        view.onHover = onHover
    }
}

final class GlassBallHoverView: NSView {
    var paneID = UUID()
    var onHover: (Bool) -> Void = { _ in }
    private var area: NSTrackingArea?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(next)
        area = next
    }

    override func mouseEntered(with event: NSEvent) { if window != nil { onHover(true) } }
    override func mouseExited(with event: NSEvent) { if window != nil { onHover(false) } }
}
