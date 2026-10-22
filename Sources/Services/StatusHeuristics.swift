import Foundation

/// Screen-text heuristics for CLI session status. They are evaluated against the last visible rows
/// of the terminal, so a prompt that scrolled away no longer counts.
enum StatusHeuristics {
    private static func compile(_ patterns: [String]) -> [NSRegularExpression] {
        patterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }

    static let question = compile([
        #"(?i)\((y/n|yes/no)\)"#, #"(?i)\[(y/n|y/N|Y/n|yes/no)\]"#,
        #"(?i)\bdo you want to\b"#, #"(?i)\bwould you like to\b"#, #"(?i)\bpress enter to\b"#,
        #"(?i)\bapprove\?"#, #"(?i)\ballow\b.*\?"#, #"(?i)\bchoose an option\b"#, #"(?i)\bselect an option\b"#,
        #"(?i)^\s*(❯|>)?\s*1\.\s*yes\b"#, #"(?i)\bconfirm\b.*\?\s*$"#, #"(?i)\benter .* to continue\b"#,
        #"(?i)\bproceed\?"#, #"(?i)\benter to confirm\b"#, #"(?i)\btrust\b.*\?"#, #"(?i)\byes, (proceed|i trust|allow)\b"#, #"(?i)waiting for (your )?(input|approval|confirmation)"#, #"(?i)\brequires? (your )?approval\b"#,
    ])

    static let busy = compile([
        #"(?i)esc to interrupt"#, #"(?i)esc to cancel"#, #"(?i)\(esc\)"#,
        #"[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]"#, #"[✻✽✶✳✢·]\s*\w+(ing|…)"#, #"(?i)\bthinking\b"#, #"(?i)\bworking\b.*\d+s"#,
        #"(?i)\b(generating|processing|running tool|executing)\b"#,
    ])

    static let quota = compile([
        #"(?i)rate limit"#, #"(?i)usage limit"#, #"(?i)\bquota\b"#, #"(?i)\b429\b"#,
        #"(?i)too many requests"#, #"(?i)limit reached"#, #"(?i)\boverloaded\b"#, #"(?i)you.ve hit your"#,
    ])

    static let shellPrompt = compile([#"[$%#>❯›]\s*$"#])

    static func firstMatch(_ regexes: [NSRegularExpression], in lines: [String]) -> String? {
        for line in lines.reversed() {
            let range = NSRange(line.startIndex..., in: line)
            for r in regexes where r.firstMatch(in: line, options: [], range: range) != nil {
                return line
            }
        }
        return nil
    }

    struct Evaluation {
        var status: SessionStatus
        var pendingQuestion: String?
    }

    static func evaluate(lines: [String], lastOutputAt: Date?, startedAt: Date?, settings: AppSettings,
                         programState: String?, now: Date = Date()) -> Evaluation {
        let tail = Array(lines.suffix(12))
        let quiet = now.timeIntervalSince(lastOutputAt ?? startedAt ?? now)

        // Programs that speak OSC 7501 are authoritative.
        if let ps = programState {
            switch ps {
            case "working": return Evaluation(status: quiet > settings.stallAfterSeconds ? .stalled : .working, pendingQuestion: nil)
            case "blocked": return Evaluation(status: .waitingForUser, pendingQuestion: firstMatch(question, in: tail))
            case "error": return Evaluation(status: .error, pendingQuestion: nil)
            case "idle", "done": return Evaluation(status: .idle, pendingQuestion: nil)
            default: break
            }
        }

        if let q = firstMatch(question, in: tail), quiet > 1.0 {
            return Evaluation(status: .waitingForUser, pendingQuestion: q.trimmingCharacters(in: .whitespaces))
        }
        if firstMatch(quota, in: tail) != nil, quiet > 1.0 {
            return Evaluation(status: .quotaWarning, pendingQuestion: nil)
        }
        if firstMatch(busy, in: Array(lines.suffix(8))) != nil {
            return Evaluation(status: quiet > settings.stallAfterSeconds ? .stalled : .working, pendingQuestion: nil)
        }
        if quiet < settings.idleAfterSeconds {
            return Evaluation(status: .working, pendingQuestion: nil)
        }
        return Evaluation(status: .idle, pendingQuestion: nil)
    }
}
