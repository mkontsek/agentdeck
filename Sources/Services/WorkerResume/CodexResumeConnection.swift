import CryptoKit
import Darwin
import Foundation

struct CodexResumeRPCError: LocalizedError {
    let method: String
    let message: String
    var errorDescription: String? { "Codex \(method) rejected: \(message)" }
}

/// Owned exclusively by a detached task. Connects to an existing server; never launches a second provider.
final class CodexResumeConnection {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    private var sequence = 0
    private var total = 0
    private var deferredEvents: [[String: Any]] = []

    init(executable: String, socket: String? = nil) throws {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "proxy"]
        if let socket { process.arguments! += ["--sock", socket] }
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.environment = ProcessInfo.processInfo.environment.filter {
            !$0.key.hasPrefix("AGENTDECK_") && !$0.key.hasPrefix("CODEX_") && !$0.key.hasPrefix("CLAUDE")
        }
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        _ = fcntl(output.fileHandleForReading.fileDescriptor, F_SETFL, O_NONBLOCK)
    }

    func close() {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        let deadline = Date().addingTimeInterval(0.3)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        try? output.fileHandleForReading.close()
    }

    func initialize() throws {
        try handshake()
        _ = try request(
            "initialize",
            [
                "clientInfo": ["name": "agentdeck_worker_resume", "version": "1.0.0"],
                "capabilities": ["experimentalApi": true],
            ])
        try send(["method": "initialized"])
    }

    func request(_ method: String, _ params: [String: Any]) throws -> [String: Any] {
        sequence += 1
        let id = sequence
        try send(["id": id, "method": method, "params": params])
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            let object = try read(deadline: deadline)
            if object["id"] as? Int == id {
                if let error = object["error"] as? [String: Any] {
                    throw CodexResumeRPCError(method: method, message: error["message"] as? String ?? "provider error")
                }
                guard let result = object["result"] as? [String: Any] else {
                    throw CoordinationError(message: "Codex returned an invalid receipt.")
                }
                return result
            }
            // This client never handles approval requests or changes approval policy.
            if object["method"] != nil { deferredEvents.append(object) }
            guard deferredEvents.count <= 4096 else {
                throw CoordinationError(message: "Codex event buffer exceeded its limit.")
            }
        }
        throw CoordinationError(message: "Codex transport timed out.")
    }

    func nextEvent(deadline: Date) throws -> [String: Any] {
        if !deferredEvents.isEmpty { return deferredEvents.removeFirst() }
        return try read(deadline: deadline)
    }

    private func send(_ object: [String: Any]) throws {
        try sendFrame(try JSONSerialization.data(withJSONObject: object), opcode: 1)
    }

    private func read(deadline: Date) throws -> [String: Any] {
        while Date() < deadline {
            let header = try take(2, deadline: deadline)
            guard header[0] & 0x70 == 0, header[1] & 0x80 == 0 else {
                throw CoordinationError(message: "Unsupported Codex WebSocket framing.")
            }
            let opcode = header[0] & 0x0f
            var length = UInt64(header[1] & 0x7f)
            if length == 126 {
                length = try take(2, deadline: deadline).reduce(0) { ($0 << 8) | UInt64($1) }
            } else if length == 127 {
                length = try take(8, deadline: deadline).reduce(0) { ($0 << 8) | UInt64($1) }
            }
            guard length <= 1_048_576, header[0] & 0x80 != 0 else {
                throw CoordinationError(
                    message: "Codex frame is oversized or fragmented; request outcome must be checked.")
            }
            let data = try take(Int(length), deadline: deadline)
            if opcode == 8 { throw CoordinationError(message: "Codex closed the shared transport.") }
            if opcode == 9 {
                try sendFrame(data, opcode: 10)
                continue
            }
            if opcode == 10 { continue }
            guard opcode == 1, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CoordinationError(message: "Unsupported Codex WebSocket message.")
            }
            return object
        }
        throw CoordinationError(message: "Codex transport timed out.")
    }

    private func handshake() throws {
        let key = Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        let request =
            "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: \(key)\r\nSec-WebSocket-Version: 13\r\n\r\n"
        try input.fileHandleForWriting.write(contentsOf: Data(request.utf8))
        var header = Data()
        let deadline = Date().addingTimeInterval(15)
        while !header.suffix(4).elementsEqual([13, 10, 13, 10]) {
            header.append(try take(1, deadline: deadline))
            guard header.count <= 16_384 else {
                throw CoordinationError(message: "Codex handshake exceeded its limit.")
            }
        }
        let expected = Data(Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8)))
            .base64EncodedString()
        let lines = String(decoding: header, as: UTF8.self).components(separatedBy: "\r\n")
        guard lines.first?.hasPrefix("HTTP/1.1 101 ") == true,
            lines.contains(where: {
                $0.lowercased().hasPrefix("sec-websocket-accept:")
                    && $0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) == expected
            })
        else {
            throw CoordinationError(message: "Existing Codex server did not accept the native WebSocket protocol.")
        }
    }

    private func sendFrame(_ data: Data, opcode: UInt8) throws {
        var frame = Data([0x80 | opcode])
        if data.count < 126 {
            frame.append(0x80 | UInt8(data.count))
        } else if data.count <= 65_535 {
            frame.append(0x80 | 126)
            frame.append(UInt8(data.count >> 8))
            frame.append(UInt8(data.count & 255))
        } else {
            frame.append(0x80 | 127)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((UInt64(data.count) >> shift) & 255))
            }
        }
        let mask = (0..<4).map { _ in UInt8.random(in: 0...255) }
        frame.append(contentsOf: mask)
        frame.append(contentsOf: data.enumerated().map { $0.element ^ mask[$0.offset % 4] })
        try input.fileHandleForWriting.write(contentsOf: frame)
    }

    private func take(_ count: Int, deadline: Date) throws -> Data {
        let fd = output.fileHandleForReading.fileDescriptor
        var bytes = [UInt8](repeating: 0, count: 16_384)
        while Date() < deadline {
            try Task.checkCancellation()
            if buffer.count >= count {
                let result = Data(buffer.prefix(count))
                buffer.removeFirst(count)
                return result
            }
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            _ = poll(&descriptor, 1, 100)
            let count = Darwin.read(fd, &bytes, bytes.count)
            if count == 0 { throw CoordinationError(message: "Codex shared transport closed or is unavailable.") }
            if count < 0 {
                if errno == EAGAIN || errno == EINTR { continue }
                throw CoordinationError(message: "Codex shared transport read failed.")
            }
            total += count
            guard total <= 16_777_216, buffer.count + count <= 1_048_576 else {
                throw CoordinationError(message: "Codex response exceeded its bounded transport budget.")
            }
            buffer.append(contentsOf: bytes.prefix(count))
        }
        throw CoordinationError(message: "Codex transport timed out; no execution claim can be made.")
    }

    static var executable: String? {
        [NSHomeDirectory() + "/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
