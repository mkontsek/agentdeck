import Darwin
import Foundation

/// A short-lived, read-only app-server client. Never starts a conversation or reads a transcript.
enum CodexUsageReader {
    static func read() async throws -> CLIUsageSnapshot {
        let worker = Task.detached(priority: .utility) { try fetch() }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func fetch() throws -> CLIUsageSnapshot {
        let candidates = [NSHomeDirectory() + "/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw UsageParseError.unavailable("Codex CLI was not found in a standard install location.")
        }
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = NSHomeDirectory() + "/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        environment = environment.filter { !$0.key.hasPrefix("AGENTDECK_") }
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            let deadline = Date().addingTimeInterval(0.5)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
        }
        func send(_ object: [String: Any]) throws {
            var bytes = try JSONSerialization.data(withJSONObject: object)
            bytes.append(10)
            try input.fileHandleForWriting.write(contentsOf: bytes)
        }
        try send([
            "id": 0, "method": "initialize",
            "params": [
                "clientInfo": ["name": "agentdeck_usage", "version": "1.0.0"],
                "capabilities": ["experimentalApi": true],
            ],
        ])
        let fd = output.fileHandleForReading.fileDescriptor
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        var buffer = Data()
        var bytes = [UInt8](repeating: 0, count: 16_384)
        let deadline = Date().addingTimeInterval(20)
        var total = 0
        while Date() < deadline {
            try Task.checkCancellation()
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            _ = poll(&descriptor, 1, 100)
            let count = Darwin.read(fd, &bytes, bytes.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EAGAIN || errno == EINTR { continue }
                break
            }
            total += count
            guard total <= 1_048_576 else {
                throw UsageParseError.unavailable("Codex usage response exceeded its size limit.")
            }
            buffer.append(contentsOf: bytes.prefix(count))
            while let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                    let id = object["id"] as? Int
                else { continue }
                if object["error"] != nil {
                    throw UsageParseError.unavailable("Codex could not read account limits. Check CLI sign-in.")
                }
                if id == 0 {
                    try send(["method": "initialized"])
                    try send(["id": 1, "method": "account/rateLimits/read"])
                } else if id == 1 {
                    return try UsageParser.codex(line)
                }
            }
        }
        throw UsageParseError.unavailable("Codex usage request timed out or the CLI exited.")
    }
}
