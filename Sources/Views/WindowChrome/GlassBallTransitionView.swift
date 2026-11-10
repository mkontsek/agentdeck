import SwiftUI

/// Animate retained layers, not terminal geometry. Only the current completion may hide native content.
@MainActor
final class GlassBallTransitionState: ObservableObject {
    @Published private(set) var visualCollapsed: Bool
    @Published private(set) var hidesContent: Bool
    @Published private(set) var isTransitioning = false
    private var revision = 0

    init(collapsed: Bool) {
        visualCollapsed = collapsed
        hidesContent = collapsed
    }

    func settle(collapsed: Bool) {
        revision += 1
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            visualCollapsed = collapsed
            hidesContent = collapsed
            isTransitioning = false
        }
    }

    func transition(to collapsed: Bool, reduceMotion: Bool) {
        guard !reduceMotion else {
            settle(collapsed: collapsed)
            return
        }
        guard visualCollapsed != collapsed || hidesContent != collapsed else { return }
        revision += 1
        let current = revision
        hidesContent = false
        isTransitioning = true
        withAnimation(WorkspaceMotion.glassBallAnimation(reduceMotion: false), completionCriteria: .removed) {
            visualCollapsed = collapsed
        } completion: { [weak self] in
            guard let self, self.revision == current else { return }
            self.hidesContent = collapsed
            self.isTransitioning = false
        }
    }
}

struct GlassBallTransitionView<Content: View, Ball: View>: View {
    let collapsed: Bool
    let size: CGSize
    let reduceMotion: Bool
    let dock: GlassBallDock
    let content: Content
    let ball: Ball
    @StateObject private var motion: GlassBallTransitionState

    init(
        collapsed: Bool, size: CGSize, reduceMotion: Bool, dock: GlassBallDock = .left,
        @ViewBuilder content: () -> Content,
        @ViewBuilder ball: () -> Ball
    ) {
        self.collapsed = collapsed
        self.size = size
        self.reduceMotion = reduceMotion
        self.dock = dock
        self.content = content()
        self.ball = ball()
        _motion = StateObject(wrappedValue: GlassBallTransitionState(collapsed: collapsed))
    }

    var body: some View {
        let compact = dock.compactFrame(in: CGRect(origin: .zero, size: size))
        ZStack(alignment: .topLeading) {
            content
                .environment(\.isGlassBallCollapsed, collapsed && motion.hidesContent)
                .environment(\.isGlassBallTransitioning, motion.isTransitioning)
                .scaleEffect(
                    x: motion.visualCollapsed ? GlassBallDock.diameter / max(1, size.width) : 1,
                    y: motion.visualCollapsed ? GlassBallDock.diameter / max(1, size.height) : 1,
                    anchor: dock.anchor
                )
                .opacity(motion.visualCollapsed ? 0 : 1)
                .allowsHitTesting(!collapsed).accessibilityHidden(collapsed)
            ball
                .offset(x: compact.minX, y: compact.minY)
                .opacity(motion.visualCollapsed ? 1 : 0)
                .allowsHitTesting(collapsed).accessibilityHidden(!collapsed)
        }
        .frame(
            width: size.width, height: size.height, alignment: .topLeading
        )
        .onAppear { motion.settle(collapsed: collapsed) }
        .onChange(of: collapsed) { _, value in motion.transition(to: value, reduceMotion: reduceMotion) }
        .onChange(of: reduceMotion) { _, _ in motion.settle(collapsed: collapsed) }
        .onDisappear { motion.settle(collapsed: collapsed) }
    }
}
