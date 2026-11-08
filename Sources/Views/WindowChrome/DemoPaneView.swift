import SwiftUI

/// Opaque synthetic presentation. Never receives names, URLs, terminal buffers or browser content.
struct DemoPaneView: View {
    let number: Int
    let split: Bool
    let movable: Bool
    let onMove: (CGSize) -> Void
    let onMoveEnd: (CGSize) -> Void
    let onMaximize: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "line.3.horizontal")
                Circle().fill(Color.green).frame(width: 7, height: 7)
                Text("Agent \(number)").fontWeight(.semibold)
                Spacer()
                Image(systemName: "ellipsis.circle")
            }
            .font(.system(size: 12)).padding(8)
            .background(Color.accentColor.opacity(0.12))
            .overlay {
                MiniWindowMoveHandle(
                    name: "Demo agent \(number)", onBegin: {}, onMove: onMove, onEnd: onMoveEnd,
                    movable: movable, drawsGrip: false, onDoubleClick: onMaximize)
            }
            Divider()
            GeometryReader { geometry in
                let horizontal = SubagentSplitLayout.automatic.isHorizontal(in: geometry.size)
                let layout = horizontal ? AnyLayout(HStackLayout(spacing: 1)) : AnyLayout(VStackLayout(spacing: 1))
                layout {
                    terminal
                    if split { browser }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipped()
        .accessibilityIdentifier("demo-pane-\(number)")
    }

    private var terminal: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Workspace / project", systemImage: "terminal").foregroundStyle(.secondary)
            Text("› Build something wonderful").foregroundStyle(Color.accentColor)
            Text("Lorem ipsum dolor sit amet, consectetur adipiscing elit.")
            Text("✓ Explore the idea\n✓ Refine the details\n✓ Verify the result").foregroundStyle(.green)
            Text("Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.").foregroundStyle(.secondary)
            Text("› Ready for the next step  ▋")
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private var browser: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("example.com", systemImage: "globe").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Ideas into action").font(.title2.bold())
            Text("Lorem ipsum dolor sit amet, consectetur adipiscing elit.").foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.16)).frame(height: 55)
                .overlay(Image(systemName: "sparkles").foregroundStyle(Color.accentColor))
            Text("Explore · Create · Collaborate").font(.caption.bold())
            Spacer(minLength: 0)
        }
        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.accentColor.opacity(0.04))
        .clipped()
    }
}
