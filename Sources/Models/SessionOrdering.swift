import Foundation

enum SessionOrdering {
    static func ordered(_ sessions: [ManagedSession]) -> [ManagedSession] {
        sessions.enumerated().sorted { lhs, rhs in
            let left = priority(lhs.element)
            let right = priority(rhs.element)
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
    }

    private enum Priority: Int, Comparable {
        case claude, codex, other
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private static func priority(_ session: ManagedSession) -> Priority {
        guard session.kind == .cli else { return .other }
        switch session.cliProfileID {
        case "claude": return .claude
        case "codex": return .codex
        default: return .other
        }
    }
}
