import Foundation
import Network

/// Only loopback fixture HTML, with bounded requests and no external services or account state.
@MainActor
final class PopupFixtureServer {
    private let listener: NWListener
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var startContinuation: CheckedContinuation<UInt16, Error>?
    private let page: String
    private let stalledPaths: Set<String>
    private(set) var requests: [String] = []

    init(page: String, stalledPaths: Set<String> = []) throws {
        self.page = page
        self.stalledPaths = stalledPaths
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> UInt16 {
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        if let port = listener.port {
                            startContinuation?.resume(returning: port.rawValue)
                            startContinuation = nil
                        }
                    case .failed(let error):
                        startContinuation?.resume(throwing: error)
                        startContinuation = nil
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    guard let self else {
                        connection.cancel()
                        return
                    }
                    connections[ObjectIdentifier(connection)] = connection
                    connection.start(queue: .main)
                    receive(connection, buffer: Data())
                }
            }
            listener.start(queue: .main)
        }
    }

    func stop() {
        listener.cancel()
        startContinuation?.resume(throwing: CancellationError())
        startContinuation = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, complete, error in
            Task { @MainActor [weak self] in
                guard let self else {
                    connection.cancel()
                    return
                }
                var buffer = buffer
                if let data { buffer.append(data) }
                guard buffer.count <= 16384, error == nil else {
                    finish(connection)
                    return
                }
                guard let separator = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                    if complete { finish(connection) } else { receive(connection, buffer: buffer) }
                    return
                }
                let headers = String(decoding: buffer[..<separator.lowerBound], as: UTF8.self)
                let length =
                    headers.components(separatedBy: "\r\n")
                    .first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) } ?? 0
                guard length >= 0, length <= 16384 else {
                    finish(connection)
                    return
                }
                guard buffer.count >= separator.upperBound + length else {
                    if complete { finish(connection) } else { receive(connection, buffer: buffer) }
                    return
                }
                requests.append(String(decoding: buffer, as: UTF8.self))
                if let path = headers.split(separator: " ").dropFirst().first, stalledPaths.contains(String(path)) {
                    return
                }
                let body = Data(page.utf8)
                var response = Data(
                    "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                        .utf8)
                response.append(body)
                connection.send(
                    content: response,
                    completion: .contentProcessed { [weak self] _ in
                        Task { @MainActor [weak self] in self?.finish(connection) }
                    })
            }
        }
    }

    private func finish(_ connection: NWConnection) {
        connection.cancel()
        connections.removeValue(forKey: ObjectIdentifier(connection))
    }
}
