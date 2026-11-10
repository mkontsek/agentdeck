import SwiftUI

struct GlassBallView: View {
    let name: String
    let status: GlassBallStatus
    let reduceMotion: Bool
    let onOpen: () -> Void
    var dock: GlassBallDock = .left
    var isPresented = true
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
            ZStack(alignment: .topLeading) {
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
                .frame(width: GlassBallDock.diameter, height: GlassBallDock.diameter)
                .shadow(color: color.opacity(pulse ? 0.8 : 0.4), radius: pulse ? 14 : 7)
                .animation(pulse ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true) : nil, value: pulse)
                .position(dock.sphereCenter)
                Text(name).font(.caption).lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, 5).background(.regularMaterial, in: Capsule())
                    .frame(maxWidth: GlassBallStatus.compactSize.width)
                    .position(dock.labelCenter)
            }
            .frame(width: GlassBallStatus.compactSize.width, height: GlassBallStatus.compactSize.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(name) · \(status.label). Click to expand; select another window to collapse.")
        .accessibilityLabel("\(name), \(status.label)")
        .accessibilityHint("Open subagent mini-window")
        .onAppear { updatePulse() }
        .onChange(of: status) { _, _ in updatePulse() }
        .onChange(of: reduceMotion) { _, _ in updatePulse() }
        .onChange(of: isPresented) { _, _ in updatePulse() }
    }

    private func updatePulse() {
        pulse = isPresented && status == .attention && !reduceMotion
    }
}
