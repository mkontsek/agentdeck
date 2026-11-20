import XCTest

/// Opt-in provider verification. Synthetic turns hit only a loopback rejection fixture, never a model.
final class LiveCodexDelegationTests: XCTestCase {
    @MainActor
    func testInstalledCodexRendersAndAppliesManagedPolicy() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["AGENTDECK_LIVE_DELEGATION_CONFIG"] == "1")
        let executable = try XCTUnwrap(CodexResumeConnection.executable)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "delegation117-" + UUID().uuidString
        )
        .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        var parent = ManagedSession(name: "Disposable policy probe", kind: .cli)
        parent.cliProfileID = "codex"
        parent.workingDirectory = directory.path
        store.addSession(parent, start: false)
        let worker = try store.delegateTask(
            from: parent.id, title: "Policy probe", instructions: "No work", start: false)
        var configurations: [[String]] = []
        for session in [parent, worker] {
            configurations.append(try configArguments(store, session: session, resume: false))
        }
        store.settings.automaticSubagents = false
        configurations.append(try configArguments(store, session: parent, resume: true))
        let inputs = configurations
        let cases = inputs.map { (arguments: $0, legacy: false) } + [(arguments: inputs[0], legacy: true)]
        var capturedRequests: [Data] = []
        let port = UInt16.random(in: 49152...65535)
        let fixture = MCPServer(port: port) { _, path, body in
            if path == "/v1/responses" { capturedRequests.append(body) }
            let rejection =
                #"{"error":{"message":"AgentDeck local request capture; no inference","type":"invalid_request_error"}}"#
            return (400, Data(rejection.utf8), "application/json")
        }
        var listening = false
        fixture.onStateChange = { listening = $0.hasPrefix("listening") }
        try fixture.start()
        defer { fixture.stop() }
        for _ in 0..<100 where !listening { try await Task.sleep(for: .milliseconds(20)) }
        guard listening else { throw ShellError.failed("Local provider fixture did not start") }
        try await Task.detached {
            let baseline = try Shell.run(
                [executable, "debug", "prompt-input", "Configuration probe only."], cwd: directory.path)
            XCTAssertTrue(
                baseline.contains("Any earlier instruction enabling proactive multi-agent delegation no longer applies")
            )
            for (index, arguments) in inputs.enumerated() {
                let output = try Shell.run(
                    [executable] + arguments + ["debug", "prompt-input", "Configuration probe only."],
                    cwd: directory.path)
                XCTAssertTrue(output.contains("<multi_agent_mode>AgentDeck manages worker orchestration."))
                XCTAssertFalse(
                    output.contains(
                        "Any earlier instruction enabling proactive multi-agent delegation no longer applies"))
                XCTAssertFalse(output.contains("<multi_agent_role>"))
                if index == 0 { XCTAssertTrue(output.contains("promptly end your turn")) }
                if index == 1 { XCTAssertTrue(output.contains("Do not delegate or recruit more agents")) }
                if index == 2 { XCTAssertTrue(output.contains("Do not create workers")) }
            }
            let validation = try Shell.run(
                [executable, "app-server", "--strict-config", "--print-startup-config"] + inputs[0], cwd: directory.path
            )
            let validated = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(validation.utf8)) as? [String: Any])
            XCTAssertNil(validated["error"])
            XCTAssertNotNil(validated["appServerVersion"])

            let socket = directory.appendingPathComponent("s.sock").path
            var server = try CodexDelegationProbeServer(executable: executable, socket: socket, directory: directory)
            defer { server.stop() }
            try await server.waitUntilListening()
            var connection = try CodexResumeConnection(executable: executable, socket: socket)
            defer { connection.close() }
            try connection.initialize()
            for probe in cases {
                let arguments = probe.arguments
                var config: [String: Any] = [
                    "mcp_servers.agentdeck.enabled": false,
                    "model": "gpt-6-astra",
                    "model_provider": "agentdeck_probe",
                    "model_providers.agentdeck_probe": [
                        "name": "AgentDeck local request capture", "base_url": "http://127.0.0.1:\(port)/v1",
                        "wire_api": "responses", "requires_openai_auth": false,
                        "request_max_retries": 0, "stream_max_retries": 0,
                    ],
                ]
                for index in stride(from: 1, to: arguments.count, by: 2) {
                    let parts = arguments[index].split(separator: "=", maxSplits: 1)
                    config[String(parts[0])] = try JSONSerialization.jsonObject(
                        with: Data(parts[1].utf8), options: [.fragmentsAllowed])
                }
                var startConfig = config
                if probe.legacy {
                    startConfig.removeValue(forKey: "features.multi_agent_v2.multi_agent_mode_hint_text")
                    startConfig.removeValue(forKey: "features.multi_agent_v2.disable_native_tools")
                }
                let started = try connection.request(
                    "thread/start", ["cwd": directory.path, "config": startConfig])
                // 0.171.0 deprecates multiAgentMode: the receipt is always explicitRequestOnly.
                // Inspect the actual outbound request instead, before the fixture rejects it.
                guard started["modelProvider"] as? String == "agentdeck_probe" else {
                    throw ShellError.failed("Refusing a probe turn outside the local fixture provider")
                }
                let thread = try XCTUnwrap(started["thread"] as? [String: Any])
                let id = try XCTUnwrap(thread["id"] as? String)
                try Self.captureTurn(connection, threadID: id)
                if probe.legacy {
                    // A loaded thread ignores replacement resume config. Restart ONLY this disposable server
                    // to prove migration of saved history after a later safe daemon restart.
                    connection.close()
                    server.stop()
                    server = try CodexDelegationProbeServer(
                        executable: executable, socket: socket + "-cold", directory: directory)
                    try await server.waitUntilListening()
                    connection = try CodexResumeConnection(executable: executable, socket: server.socket)
                    try connection.initialize()
                }
                let resumed = try connection.request(
                    "thread/resume", ["threadId": id, "excludeTurns": true, "config": config])
                guard resumed["modelProvider"] as? String == "agentdeck_probe" else {
                    throw ShellError.failed("Refusing a resumed probe outside the local fixture provider")
                }
                try Self.captureTurn(connection, threadID: id)
            }
        }.value
        guard capturedRequests.count == cases.count * 2 else {
            XCTFail("Expected eight local requests, captured \(capturedRequests.count)")
            return
        }
        for (index, body) in capturedRequests.enumerated() {
            let request = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let text = Self.strings(in: request["input"] ?? []).joined(separator: "\n")
            if cases[index / 2].legacy, index.isMultiple(of: 2) {
                XCTAssertTrue(
                    text.contains("Any earlier instruction enabling proactive multi-agent delegation no longer applies")
                )
                continue
            }
            let key = "features.multi_agent_v2.multi_agent_mode_hint_text="
            let encoded = try XCTUnwrap(cases[index / 2].arguments.first { $0.hasPrefix(key) })
            let expected = try JSONDecoder().decode(String.self, from: Data(encoded.dropFirst(key.count).utf8))
            let latestMode = try XCTUnwrap(text.range(of: "<multi_agent_mode>", options: .backwards))
            XCTAssertTrue(
                text[latestMode.lowerBound...].hasPrefix("<multi_agent_mode>" + expected + "</multi_agent_mode>"))
            if !cases[index / 2].legacy {
                XCTAssertFalse(
                    text.contains("Any earlier instruction enabling proactive multi-agent delegation no longer applies")
                )
                XCTAssertFalse(text.contains("<multi_agent_role>"))
            }
            // Cold resume preserves historical instructions, but appends the current mode and removes native tools.
            let toolValues = Self.strings(in: request["tools"] ?? [])
            XCTAssertFalse(toolValues.contains("spawn_agent"))
            XCTAssertFalse(toolValues.contains("collaboration"))
        }
        print(
            "LIVE_DELEGATION117: checked baseline, strict config, 3 rendered policies and 8 local start/resume requests including legacy cold resume; no external inference or tools executed."
        )
    }

    private static func captureTurn(_ connection: CodexResumeConnection, threadID: String) throws {
        _ = try connection.request(
            "turn/start", ["threadId": threadID, "input": [["type": "text", "text": "Local configuration probe."]]])
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            let event = try connection.nextEvent(deadline: deadline)
            if event["method"] as? String == "turn/completed",
                let params = event["params"] as? [String: Any], params["threadId"] as? String == threadID
            {
                return
            }
        }
        throw ShellError.failed("Local provider capture did not finish")
    }

    private static func strings(in value: Any) -> [String] {
        if let value = value as? String { return [value] }
        if let values = value as? [Any] { return values.flatMap { strings(in: $0) } }
        if let values = value as? [String: Any] { return values.values.flatMap { strings(in: $0) } }
        return []
    }

    @MainActor
    private func configArguments(_ store: AppStore, session: ManagedSession, resume: Bool) throws -> [String] {
        let stub = "codex() { printf '%s\\0' \"$@\"; }\n"
        let arguments = try Shell.run([
            "/bin/zsh", "-f", "-c", stub + store.launchCommand(for: session, resume: resume),
        ])
        .split(separator: "\0").map(String.init)
        return arguments.indices.filter { arguments[$0] == "-c" }.flatMap { ["-c", arguments[$0 + 1]] }
    }
}
