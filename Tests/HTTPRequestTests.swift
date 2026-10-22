import XCTest

final class HTTPRequestTests: XCTestCase {
    private func request(_ headers: String = "", body: String = "") -> Data {
        Data("POST /mcp/test?q=1 HTTP/1.1\r\nHost: 127.0.0.1:4820\r\n\(headers)\r\n\(body)".utf8)
    }

    func testFragmentedUnicodeBodyAndNonzeroDataIndex() throws {
        let body = Data("{\"message\":\"čau 👋\"}".utf8)
        let header = request("Content-Length: \(body.count)\r\n")
        XCTAssertNil(try HTTPRequest.parse(header + body.prefix(3)))
        var wire = Data([0, 1, 2]) + header + body
        wire.removeFirst(3)
        let parsed = try XCTUnwrap(HTTPRequest.parse(wire))
        XCTAssertEqual(parsed.body, body)
        XCTAssertEqual(parsed.path, "/mcp/test")
    }

    func testInvalidLengthsAndAmbiguousFraming() {
        for length in ["-1", "+1", "no", "99999999999999999999999999", ""] {
            XCTAssertThrowsError(try HTTPRequest.parse(request("Content-Length: \(length)\r\n")))
        }
        XCTAssertThrowsError(try HTTPRequest.parse(request("Content-Length: 1\r\nContent-Length: 2\r\n", body: "ab")))
        XCTAssertThrowsError(try HTTPRequest.parse(request("Transfer-Encoding: chunked\r\n")))
        XCTAssertThrowsError(try HTTPRequest.parse(Data("nonsense\r\n\r\n".utf8)))
    }

    func testLimits() {
        XCTAssertThrowsError(try HTTPRequest.parse(Data(repeating: 65, count: HTTPRequest.maximumHeaderBytes + 1)))
        XCTAssertThrowsError(try HTTPRequest.parse(request("Content-Length: \(HTTPRequest.maximumBodyBytes + 1)\r\n")))
    }

    func testOriginsAndDNSRebinding() throws {
        XCTAssertTrue(try XCTUnwrap(HTTPRequest.parse(request())).permitsLocalAccess(port: 4820))
        XCTAssertTrue(
            try XCTUnwrap(HTTPRequest.parse(request("Origin: http://localhost:4820\r\n"))).permitsLocalAccess(
                port: 4820))
        for origin in ["https://evil.example", "null", "http://localhost:1234", "http://127.0.0.1:4820.evil.example"] {
            XCTAssertFalse(
                try XCTUnwrap(HTTPRequest.parse(request("Origin: \(origin)\r\n"))).permitsLocalAccess(port: 4820))
        }
        let rebinding = Data("GET / HTTP/1.1\r\nHost: evil.example:4820\r\n\r\n".utf8)
        XCTAssertFalse(try XCTUnwrap(HTTPRequest.parse(rebinding)).permitsLocalAccess(port: 4820))
    }
}
