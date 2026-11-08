import Foundation

enum ClaudeUsageReader {
    private static let credentials = UsageCredentialCache { try credential() }

    static func read() async throws -> CLIUsageSnapshot {
        let token = try await credentials.token()
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            throw UsageParseError.unavailable("Invalid provider endpoint.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Ephemeral sessions never borrow browser cookies or persist credentials/responses.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: NoUsageRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 || code == 403 { await credentials.invalidate() }
            throw UsageParseError.unavailable(
                "Claude usage unavailable (HTTP \(code)). Check CLI sign-in or retry later.")
        }
        guard data.count <= 1_048_576 else {
            throw UsageParseError.unavailable("Claude usage response exceeded its size limit.")
        }
        return try UsageParser.claude(data)
    }

    private static func credential() throws -> String {
        if let data = try? NoninteractiveKeychain.data(service: "Claude Code-credentials"),
            let token = accessToken(in: data)
        {
            return token
        }
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/.claude/.credentials.json")
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 65_536,
            let data = try? Data(contentsOf: url), let token = accessToken(in: data)
        {
            return token
        }
        throw UsageParseError.unavailable(
            "Claude usage credentials are unavailable without Keychain interaction. Check usage in Claude Code; AgentDeck will not show an access prompt."
        )
    }

    private static func accessToken(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = object["claudeAiOauth"] as? [String: Any], let token = oauth["accessToken"] as? String,
            !token.isEmpty
        else {
            return nil
        }
        if let expiresAt = oauth["expiresAt"] as? Double, expiresAt <= Date().timeIntervalSince1970 * 1000 {
            return nil
        }
        return token
    }
}

final class NoUsageRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
