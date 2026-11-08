import Foundation

struct UsageWindow: Identifiable, Equatable, Sendable {
    var id: String
    var label: String
    var usedPercent: Double
    var resetsAt: Date?
    var limit: String = "Plan allowance"
}

struct CLIUsageSnapshot: Equatable, Sendable {
    var providerID: String
    var windows: [UsageWindow] = []
    var observedAt: Date?
    var source: String
    var detail: String = ""
    var error: String?
}

enum UsageParseError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        }
    }
}

enum UsageParser {
    static func codex(_ data: Data, now: Date = Date()) throws -> CLIUsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageParseError.unavailable("Codex returned an unrecognized response.")
        }
        let result = root["result"] as? [String: Any] ?? root
        var buckets = result["rateLimitsByLimitId"] as? [String: [String: Any]] ?? [:]
        if buckets.isEmpty, let bucket = result["rateLimits"] as? [String: Any] { buckets["codex"] = bucket }
        var windows: [UsageWindow] = []
        for (id, bucket) in buckets.sorted(by: { $0.key < $1.key }) {
            for key in ["primary", "secondary"] {
                guard let window = bucket[key] as? [String: Any], let used = window["usedPercent"] as? Double,
                    used.isFinite, (0...100).contains(used)
                else { continue }
                let minutes = window["windowDurationMins"] as? Int
                let label = minutes.map(windowLabel) ?? key.capitalized
                let bucketName = bucket["limitName"] as? String ?? id
                let reset = (window["resetsAt"] as? Double).flatMap {
                    $0.isFinite && $0 > 0 ? Date(timeIntervalSince1970: $0) : nil
                }
                windows.append(
                    UsageWindow(
                        id: "\(id)-\(key)", label: "\(bucketName) · \(label)", usedPercent: used, resetsAt: reset))
            }
        }
        guard !windows.isEmpty else {
            throw UsageParseError.unavailable(
                "No account limits reported. API-key accounts may not expose subscription quotas.")
        }
        let resetCount = (result["rateLimitResetCredits"] as? [String: Any])?["availableCount"] as? Int
        return CLIUsageSnapshot(
            providerID: "codex", windows: windows, observedAt: now,
            source: "Codex account/rateLimits/read", detail: resetCount.map { "\($0) earned resets available" } ?? "")
    }

    static func claude(_ data: Data, now: Date = Date()) throws -> CLIUsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageParseError.unavailable("Claude returned an unrecognized response.")
        }
        let formatter = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let labels = [
            "five_hour": "5 hours", "seven_day": "7 days", "seven_day_opus": "Opus · 7 days",
            "seven_day_sonnet": "Sonnet · 7 days", "seven_day_oauth_apps": "OAuth apps · 7 days",
            "seven_day_cowork": "Cowork · 7 days",
        ]
        var windows: [UsageWindow] = []
        for key in labels.keys.sorted() {
            guard let window = root[key] as? [String: Any], let used = window["utilization"] as? Double,
                used.isFinite, (0...100).contains(used)
            else { continue }
            let reset = (window["resets_at"] as? String).flatMap {
                fractional.date(from: $0) ?? formatter.date(from: $0)
            }
            windows.append(UsageWindow(id: key, label: labels[key] ?? key, usedPercent: used, resetsAt: reset))
        }
        guard !windows.isEmpty else { throw UsageParseError.unavailable("No subscription usage windows reported.") }
        return CLIUsageSnapshot(providerID: "claude", windows: windows, observedAt: now, source: "Claude OAuth usage")
    }

    static func windowLabel(_ minutes: Int) -> String {
        if minutes >= 1440, minutes % 1440 == 0 { return "\(minutes / 1440) days" }
        if minutes >= 60, minutes % 60 == 0 { return "\(minutes / 60) hours" }
        return "\(minutes) minutes"
    }

    static func gemini(_ data: Data, now: Date = Date()) throws -> CLIUsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let buckets = root["buckets"] as? [[String: Any]]
        else {
            throw UsageParseError.unavailable("Gemini did not report quota buckets.")
        }
        let formatter = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let windows = buckets.enumerated().compactMap { index, bucket -> UsageWindow? in
            guard let remaining = bucket["remainingFraction"] as? Double, remaining.isFinite,
                (0...1).contains(remaining)
            else { return nil }
            let reset = (bucket["resetTime"] as? String).flatMap {
                fractional.date(from: $0) ?? formatter.date(from: $0)
            }
            let label = bucket["modelId"] as? String ?? "Model allowance"
            let amount = bucket["remainingAmount"] as? String
            let limit =
                amount.map { "\($0) \(bucket["tokenType"] as? String ?? "units") remaining" } ?? "Plan allowance"
            return UsageWindow(
                id: "\(label)-\(index)", label: label, usedPercent: (1 - remaining) * 100, resetsAt: reset, limit: limit
            )
        }
        guard !windows.isEmpty else { throw UsageParseError.unavailable("Gemini did not report usable quota windows.") }
        return CLIUsageSnapshot(
            providerID: "gemini", windows: windows, observedAt: now, source: "Gemini Code Assist quota")
    }
}
