import Foundation
import Network

/// Minimal HTTP/1.1 server on loopback that carries the MCP "streamable HTTP" transport (JSON responses only).
final class MCPServer {
    typealias Handler = @MainActor (_ method: String, _ path: String, _ body: Data) -> (status: Int, body: Data, contentType: String)

    let port: UInt16
    private let handler: Handler
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "io.kontsek.agentdeck.mcp")

    init(port: UInt16, handler: @escaping Handler) {
        self.port = port
        self.handler = handler
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        let l = try NWListener(using: params)
        l.newConnectionHandler = { [weak self] conn in self?.serve(conn) }
        l.stateUpdateHandler = { state in
            if case .failed(let e) = state { NSLog("MCP listener failed: \(e)") }
        }
        l.start(queue: queue)
        listener = l
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func serve(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            self.drain(conn, &buf)
            if isComplete || error != nil { conn.cancel(); return }
            self.receive(conn, buffer: buf)
        }
    }

    private func drain(_ conn: NWConnection, _ buf: inout Data) {
        let sep = Data("\r\n\r\n".utf8)
        while let headerEnd = buf.range(of: sep) {
            let head = String(decoding: buf[buf.startIndex..<headerEnd.lowerBound], as: UTF8.self)
            let lines = head.components(separatedBy: "\r\n")
            let parts = (lines.first ?? "").split(separator: " ")
            let method = parts.count > 0 ? String(parts[0]) : "GET"
            let target = parts.count > 1 ? String(parts[1]) : "/"
            var headers: [String: String] = [:]
            for l in lines.dropFirst() {
                if let i = l.firstIndex(of: ":") {
                    headers[l[..<i].trimmingCharacters(in: .whitespaces).lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
                }
            }
            let length = Int(headers["content-length"] ?? "0") ?? 0
            let bodyStart = headerEnd.upperBound
            guard buf.count - (bodyStart - buf.startIndex) >= length else { return }
            let body = buf.subdata(in: bodyStart..<(bodyStart + length))
            buf.removeSubrange(buf.startIndex..<(bodyStart + length))
            let path = String(target.split(separator: "?").first ?? "/")
            Task { @MainActor [handler] in
                let r = handler(method, path, body)
                self.respond(conn, status: r.status, body: r.body, contentType: r.contentType)
            }
        }
    }

    private func respond(_ conn: NWConnection, status: Int, body: Data, contentType: String) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 202: reason = "Accepted"
        case 400: reason = "Bad Request"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        default: reason = "Error"
        }
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: keep-alive\r\nAccess-Control-Allow-Origin: *\r\n\r\n"
        conn.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in })
    }
}
