import Foundation

/// Uses the same read-only Code Assist quota methods as Gemini CLI. Never onboards a project or refreshes a login.
enum GeminiUsageReader {
    static func read() async throws -> CLIUsageSnapshot {
        let worker = Task.detached(priority: .utility) { () throws -> String in
            let url = URL(fileURLWithPath: NSHomeDirectory() + "/.gemini/oauth_creds.json")
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 65_536,
                let data = try? Data(contentsOf: url),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let token = object["access_token"] as? String, !token.isEmpty
            else {
                throw UsageParseError.unavailable(
                    "Gemini OAuth sign-in is unavailable. API-key accounts do not expose Code Assist quotas.")
            }
            if let expiry = object["expiry_date"] as? Double, expiry / 1000 < Date().timeIntervalSince1970 {
                throw UsageParseError.unavailable("Gemini sign-in needs refreshing. Open the CLI, then refresh usage.")
            }
            return token
        }
        let token = try await worker.value
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: NoUsageRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        func request(_ method: String, body: [String: Any]) async throws -> Data {
            guard let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:\(method)") else {
                throw UsageParseError.unavailable("Invalid provider endpoint.")
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 1_048_576 else {
                throw UsageParseError.unavailable(
                    "Gemini quota request failed. Check the CLI’s sign-in and account access.")
            }
            return data
        }
        let metadata = ["ideType": "IDE_UNSPECIFIED", "platform": "PLATFORM_UNSPECIFIED", "pluginType": "GEMINI"]
        let loaded = try await request("loadCodeAssist", body: ["metadata": metadata, "mode": "HEALTH_CHECK"])
        let root = try JSONSerialization.jsonObject(with: loaded) as? [String: Any]
        guard let project = root?["cloudaicompanionProject"] as? String, !project.isEmpty else {
            throw UsageParseError.unavailable(
                "No existing Code Assist project was reported. Open Gemini CLI to finish its setup.")
        }
        return try UsageParser.gemini(await request("retrieveUserQuota", body: ["project": project]))
    }
}
