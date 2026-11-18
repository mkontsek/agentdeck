import SwiftUI

/// Mini-window border geometry. Session content keeps a constant inset, so the focus ring never covers it and a
/// focus change never resizes a terminal.
enum PaneChrome {
    static let cornerRadius: CGFloat = 8
    static let idleBorderWidth: CGFloat = 1.5
    static let focusRingWidth: CGFloat = 4
    /// Clears the ring on straight edges and inside its rounded corners, which need
    /// `cornerRadius - (cornerRadius - focusRingWidth) / sqrt(2)`, about 5.2 pt.
    static let contentInset: CGFloat = 6

    static func borderWidth(focused: Bool) -> CGFloat { focused ? focusRingWidth : idleBorderWidth }

    /// The edges of one session's content that meet the mini-window border. The header covers the top edge and a
    /// split divider covers the edge between two sessions.
    static func borderEdges(isSplit: Bool, isHorizontal: Bool, isFirst: Bool) -> Edge.Set {
        guard isSplit else { return [.horizontal, .bottom] }
        if isHorizontal { return isFirst ? [.leading, .bottom] : [.trailing, .bottom] }
        return isFirst ? .horizontal : [.horizontal, .bottom]
    }
}
