import Foundation

/// Bounded HTTP/1.1 framing for the local JSON transport. Chunked requests are unsupported.
struct HTTPRequest {
    static let maximumHeaderBytes = 16 * 1024
    static let maximumBodyBytes = 1024 * 1024

    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    enum ParseError: Error {
        case malformed, tooLarge
    }

    static func parse(_ data: Data) throws -> HTTPRequest? {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else {
            if data.count > maximumHeaderBytes { throw ParseError.tooLarge }
            return nil
        }
        guard data.distance(from: data.startIndex, to: separator.upperBound) <= maximumHeaderBytes else {
            throw ParseError.tooLarge
        }
        guard let header = String(data: data[..<separator.lowerBound], encoding: .utf8) else {
            throw ParseError.malformed
        }
        let lines = header.components(separatedBy: "\r\n")
        let requestLine = (lines.first ?? "").split(separator: " ")
        guard requestLine.count == 3, requestLine[2] == "HTTP/1.1", requestLine[1].hasPrefix("/") else {
            throw ParseError.malformed
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { throw ParseError.malformed }
            let name = String(line[..<colon]).lowercased()
            guard !name.isEmpty, !name.contains(where: { $0.isWhitespace }), headers[name] == nil else {
                throw ParseError.malformed
            }
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard headers["transfer-encoding"] == nil, headers["host"] != nil else { throw ParseError.malformed }
        let rawLength = headers["content-length"] ?? "0"
        guard !rawLength.isEmpty, rawLength.utf8.allSatisfy({ (48...57).contains($0) }),
            let length = Int(rawLength)
        else { throw ParseError.malformed }
        guard length <= maximumBodyBytes else { throw ParseError.tooLarge }
        let start = separator.upperBound
        guard data.distance(from: start, to: data.endIndex) >= length else { return nil }
        let end = data.index(start, offsetBy: length)
        return HTTPRequest(
            method: String(requestLine[0]),
            path: String(requestLine[1].split(separator: "?", maxSplits: 1)[0]),
            headers: headers, body: Data(data[start..<end]))
    }

    /// Native clients omit Origin. Web callers must originate at this exact loopback endpoint.
    func permitsLocalAccess(port: UInt16) -> Bool {
        let authorities = ["127.0.0.1:\(port)", "localhost:\(port)"]
        guard let host = headers["host"], authorities.contains(host.lowercased()) else { return false }
        guard let origin = headers["origin"] else { return true }
        return authorities.contains { origin == "http://\($0)" }
    }
}
