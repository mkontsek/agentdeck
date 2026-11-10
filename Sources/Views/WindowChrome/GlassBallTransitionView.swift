import SwiftUI

/// Animate retained layers, not terminal geometry. Only the current completion may hide native content.
@MainActor
final class GlassBallTransitionState: ObservableObject {
    @Published private(set) var visualCollapsed: Bool
    @Published private(set) var hidesContent: Bool
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
        withAnimation(WorkspaceMotion.animation(reduceMotion: false), completionCriteria: .removed) {
            visualCollapsed = collapsed
        } completion: { [weak self] in
            guard let self, self.revision == current else { return }
            self.hidesContent = collapsed
        }
    }
}

struct GlassBallTransitionView<Content: View, Ball: View>: View {
    let collapsed: Bool
    let size: CGSize
    let reduceMotion: Bool
    let content: Content
    let ball: Ball
    @StateObject private var motion: GlassBallTransitionState

    init(
        collapsed: Bool, size: CGSize, reduceMotion: Bool, @ViewBuilder content: () -> Content,
        @ViewBuilder ball: () -> Ball
    ) {
        self.collapsed = collapsed
        self.size = size
        self.reduceMotion = reduceMotion
        self.content = content()
        self.ball = ball()
        _motion = StateObject(wrappedValue: GlassBallTransitionState(collapsed: collapsed))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
                .environment(\.isGlassBallCollapsed, collapsed && motion.hidesContent)
                .scaleEffect(
                    x: motion.visualCollapsed ? GlassBallStatus.compactSize.width / max(1, size.width) : 1,
                    y: motion.visualCollapsed ? GlassBallStatus.compactSize.height / max(1, size.height) : 1,
                    anchor: .topLeading
                )
                .opacity(motion.visualCollapsed ? 0 : 1)
                .allowsHitTesting(!collapsed).accessibilityHidden(collapsed)
            if motion.visualCollapsed {
                ball.transition(.opacity.combined(with: .scale(scale: 0.65, anchor: .topLeading)))
                    .allowsHitTesting(collapsed).accessibilityHidden(!collapsed)
            }
        }
        .frame(
            width: collapsed ? GlassBallStatus.compactSize.width : size.width,
            height: collapsed ? GlassBallStatus.compactSize.height : size.height, alignment: .topLeading
        )
        .onAppear { motion.settle(collapsed: collapsed) }
        .onChange(of: collapsed) { _, value in motion.transition(to: value, reduceMotion: reduceMotion) }
        .onChange(of: reduceMotion) { _, _ in motion.settle(collapsed: collapsed) }
        .onDisappear { motion.settle(collapsed: collapsed) }
    }
}
