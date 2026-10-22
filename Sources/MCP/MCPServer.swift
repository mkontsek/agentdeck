import Foundation
import Network

/// Loopback MCP transport. Each connection carries one request and closes after its response.
@MainActor
final class MCPServer {
    typealias Handler =
        @MainActor (_ method: String, _ path: String, _ body: Data) async -> (
            status: Int, body: Data, contentType: String
        )

    let port: UInt16
    var onStateChange: ((String) -> Void)?
    private let handler: Handler
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var deadlines: [UUID: Task<Void, Never>] = [:]

    init(port: UInt16, handler: @escaping Handler) {
        self.port = port
        self.handler = handler
    }

    func start() throws {
        stop()
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        guard let endpointPort = NWEndpoint.Port(rawValue: port), port > 0 else {
            throw ShellError.failed("MCP port must be between 1 and 65535")
        }
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: endpointPort)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self, weak listener] connection in
            Task { @MainActor in
                guard let self, let listener, self.listener === listener else {
                    connection.cancel()
                    return
                }
                self.serve(connection)
            }
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            Task { @MainActor in
                guard let self, let listener, self.listener === listener else { return }
                switch state {
                case .ready: self.onStateChange?("listening on http://127.0.0.1:\(self.port)")
                case .failed(let error):
                    self.stop()
                    self.onStateChange?("failed: \(error.localizedDescription)")
                default: break
                }
            }
        }
        self.listener = listener
        listener.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        for deadline in deadlines.values { deadline.cancel() }
        deadlines.removeAll()
    }

    private func close(_ id: UUID) {
        connections.removeValue(forKey: id)?.cancel()
        deadlines.removeValue(forKey: id)?.cancel()
    }

    private func serve(_ connection: NWConnection) {
        guard connections.count < 64 else {
            connection.cancel()
            return
        }
        let id = UUID()
        connections[id] = connection
        deadlines[id] = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            self?.close(id)
        }
        connection.start(queue: .main)
        receive(id, buffer: Data())
    }

    private func receive(_ id: UUID, buffer: Data) {
        guard let connection = connections[id] else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.connections[id] != nil else { return }
                var buffer = buffer
                if let data { buffer.append(data) }
                do {
                    if let request = try HTTPRequest.parse(buffer) {
                        guard request.permitsLocalAccess(port: self.port) else {
                            self.respond(id, status: 403, body: Data(), contentType: "text/plain")
                            return
                        }
                        // The deadline guards slow senders, not slow tools: browser tools may legitimately wait.
                        self.deadlines.removeValue(forKey: id)?.cancel()
                        let response = await self.handler(request.method, request.path, request.body)
                        guard self.connections[id] != nil else { return }
                        self.respond(
                            id, status: response.status, body: response.body, contentType: response.contentType)
                        return
                    }
                } catch {
                    let status = (error as? HTTPRequest.ParseError) == .tooLarge ? 413 : 400
                    self.respond(id, status: status, body: Data(), contentType: "text/plain")
                    return
                }
                if complete || error != nil { self.close(id) } else { self.receive(id, buffer: buffer) }
            }
        }
    }

    private func respond(_ id: UUID, status: Int, body: Data, contentType: String) {
        guard let connection = connections[id] else { return }
        let reason = HTTPURLResponse.localizedString(forStatusCode: status)
        let header =
            "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(
            content: Data(header.utf8) + body,
            completion: .contentProcessed { [weak self] _ in
                Task { @MainActor in self?.close(id) }
            })
    }
}
