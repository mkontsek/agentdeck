import Darwin
import Foundation
import XCTest

final class BrowserLogSummaryTests: XCTestCase {
    @MainActor
    func testTypedTextScriptsAndQueryStringsStayOutOfTheLog() {
        XCTAssertEqual(
            AppStore.browserLogSummary(name: "browser_type", args: ["text": "hunter2", "selector": "#password"]),
            "selector=#password, text=<7 chars>")
        XCTAssertEqual(
            AppStore.browserLogSummary(name: "browser_eval", args: ["script": "document.cookie"]),
            "script=<15 chars>")
        XCTAssertEqual(
            AppStore.browserLogSummary(
                name: "browser_navigate", args: ["url": "https://example.com/reset?token=abc#frag", "wait_ms": 10]),
            "url=https://example.com/reset, wait_ms=10")
        XCTAssertEqual(
            AppStore.browserLogSummary(name: "browser_click", args: ["text": "Sign in"]), "text=Sign in")
    }
}

final class MCPServerTests: XCTestCase {
    private static func exchange(port: UInt16, request: String) throws -> String {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw ShellError.failed("socket failed") }
        defer { close(descriptor) }
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else { throw ShellError.failed("connect failed: \(errno)") }
        let bytes = Array(request.utf8)
        let written = bytes.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        guard written == bytes.count else { throw ShellError.failed("write failed") }
        shutdown(descriptor, SHUT_WR)
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count == 0 { break }
            guard count > 0 else { throw ShellError.failed("read timed out: \(errno)") }
            response.append(contentsOf: buffer.prefix(count))
        }
        return String(decoding: response, as: UTF8.self)
    }

    @MainActor
    func testLiveTransportRejectsBadInputAndSurvives() async throws {
        let port = UInt16.random(in: 49152...65535)
        var status = "starting"
        var calls = 0
        let server = MCPServer(port: port) { _, _, body in
            calls += 1
            return (200, body, "application/json")
        }
        server.onStateChange = { status = $0 }
        try server.start()
        defer { server.stop() }
        for _ in 0..<100 where status == "starting" { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(status.hasPrefix("listening"), status)
        func wire(_ extra: String, body: String = "") -> String {
            "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n\(extra)\r\n\(body)"
        }
        let invalidLength = wire("Content-Length: -1\r\n")
        let invalidResponse = try await Shell.offMain { try Self.exchange(port: port, request: invalidLength) }
        XCTAssertTrue(invalidResponse.hasPrefix("HTTP/1.1 400"))
        let hostile = wire("Content-Length: 2\r\nOrigin: https://evil.example\r\n", body: "{}")
        let forbidden = try await Shell.offMain { try Self.exchange(port: port, request: hostile) }
        XCTAssertTrue(forbidden.hasPrefix("HTTP/1.1 403"))
        let valid = wire("Content-Length: 2\r\n", body: "{}")
        let success = try await Shell.offMain { try Self.exchange(port: port, request: valid) }
        XCTAssertTrue(success.hasPrefix("HTTP/1.1 200"))
        XCTAssertTrue(success.hasSuffix("{}"))
        XCTAssertFalse(success.contains("Access-Control-Allow-Origin"))
        XCTAssertEqual(calls, 1)
        server.stop()
        do {
            _ = try await Shell.offMain { try Self.exchange(port: port, request: valid) }
            XCTFail("Stopped server accepted a request")
        } catch {}
    }
}
