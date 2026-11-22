import Darwin
import Foundation

/// Owned only by the detached integration fixture. Never connects to the user's daemon or provider home.
final class CodexDelegationProbeServer {
    let socket: String
    private let process = Process()
    private let exited = DispatchSemaphore(value: 0)

    init(executable: String, socket: String, directory: URL) throws {
        self.socket = socket
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--listen", "unix://" + socket]
        process.currentDirectoryURL = directory
        process.standardInput = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.environment = ProcessInfo.processInfo.environment.filter {
            !$0.key.hasPrefix("AGENTDECK_") && !$0.key.hasPrefix("CODEX_") && !$0.key.hasPrefix("CLAUDE")
        }
        // Resumption requires saved history. Use a private temporary provider home without copying credentials.
        let providerHome = directory.appendingPathComponent("provider")
        try FileManager.default.createDirectory(at: providerHome, withIntermediateDirectories: true)
        process.environment?["CODEX_HOME"] = providerHome.path
        process.terminationHandler = { [exited] _ in exited.signal() }
        try process.run()
    }

    func waitUntilListening() async throws {
        for _ in 0..<500 where !FileManager.default.fileExists(atPath: socket) {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard FileManager.default.fileExists(atPath: socket) else {
            throw ShellError.failed("Disposable Codex socket did not open")
        }
    }

    /// Bounded synchronous teardown runs on the detached fixture worker, never the main actor.
    func stop() {
        guard process.isRunning else { return }
        process.terminate()
        if exited.wait(timeout: .now() + .seconds(2)) == .timedOut, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            _ = exited.wait(timeout: .now() + .seconds(2))
        }
    }
}
