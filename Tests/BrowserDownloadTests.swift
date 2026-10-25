import AppKit
import Network
import XCTest

final class BrowserDownloadTests: XCTestCase {
    func testDownloadDirectoryDefaultsToMacDownloads() {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .standardizedFileURL.path
        XCTAssertEqual(DownloadLocation.directory(from: "").path, downloads)
        XCTAssertEqual(DownloadLocation.directory(from: "   ").path, downloads)
        XCTAssertEqual(DownloadLocation.directory(from: DownloadLocation.defaultSetting).path, downloads)
        XCTAssertEqual(AppSettings().downloadDirectory, DownloadLocation.defaultSetting)
    }

    func testMissingOrBlankDownloadDirectoryDecodesToMacDefault() throws {
        let missing = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(missing.downloadDirectory, DownloadLocation.defaultSetting)
        let blank = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"downloadDirectory":"  "}"#.utf8))
        XCTAssertEqual(blank.downloadDirectory, DownloadLocation.defaultSetting)
        var custom = AppSettings()
        custom.downloadDirectory = "~/Desktop"
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(custom))
        XCTAssertEqual(decoded.downloadDirectory, "~/Desktop")
    }

    func testDestinationStaysInsideTheChosenFolder() {
        let folder = URL(fileURLWithPath: "/tmp/agentdeck-downloads", isDirectory: true)
        XCTAssertEqual(
            DownloadLocation.destinationURL(
                directory: folder, suggestedFilename: "../secret.txt", exists: { _ in false }
            )
            .path,
            "/tmp/agentdeck-downloads/secret.txt")
        XCTAssertEqual(
            DownloadLocation.filename(suggested: ".."), "download")
        XCTAssertEqual(
            DownloadLocation.filename(suggested: ""), "download")
        var taken: Set<String> = [folder.appendingPathComponent("report.pdf").path]
        let first = DownloadLocation.destinationURL(directory: folder, suggestedFilename: "report.pdf") {
            taken.contains($0.path)
        }
        XCTAssertEqual(first.lastPathComponent, "report (1).pdf")
        taken.insert(first.path)
        let second = DownloadLocation.destinationURL(directory: folder, suggestedFilename: "report.pdf") {
            taken.contains($0.path)
        }
        XCTAssertEqual(second.lastPathComponent, "report (2).pdf")
        let relative = DownloadLocation.directory(from: "AgentDeckDownloads")
        XCTAssertEqual(
            relative.path, URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("AgentDeckDownloads").path)
    }

    @MainActor
    func testBrowserSavesAttachmentIntoTheConfiguredDirectory() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let downloads = root.appendingPathComponent("downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
        let server = try AttachmentServer(body: "hello from agentdeck", filename: "agentdeck-download.txt")
        let port = try await server.start()
        defer {
            server.stop()
            store.shutdown()
            if let session = store.sessions.first { BrowserHost.deleteProfile(session.browserProfileID) }
            try? FileManager.default.removeItem(at: root)
        }
        store.settings.downloadDirectory = downloads.path
        var session = ManagedSession(name: "Download", kind: .browser)
        session.browserProfileMode = .isolated
        session.url = "http://127.0.0.1:\(port)/file.txt"
        store.addSession(session)
        let saved = downloads.appendingPathComponent("agentdeck-download.txt")
        var contents = ""
        for _ in 0..<100 {
            contents = (try? String(contentsOf: saved, encoding: .utf8)) ?? ""
            if contents == "hello from agentdeck" { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(contents, "hello from agentdeck", store.log.map(\.message).joined(separator: "\n"))
        XCTAssertTrue(store.log.contains { $0.message.contains("saved agentdeck-download.txt") })
        XCTAssertNil(store.lastError)
    }
}

private final class AttachmentServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "agentdeck.download.test")
    private let body: Data
    private let filename: String

    init(body: String, filename: String) throws {
        self.body = Data(body.utf8)
        self.filename = filename
        listener = try NWListener(using: .tcp, on: .any)
    }

    func start() async throws -> UInt16 {
        let listener = listener
        let body = body
        let filename = filename
        let queue = queue
        return try await withCheckedThrowingContinuation { continuation in
            let gate = NSLock()
            var resumed = false
            func resume(_ result: Result<UInt16, Error>) {
                gate.lock()
                defer { gate.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(with: result)
            }
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resume(.success(listener.port?.rawValue ?? 0))
                case .failed(let error):
                    resume(.failure(error))
                default:
                    break
                }
            }
            listener.newConnectionHandler = { connection in
                connection.start(queue: queue)
                Self.serve(connection: connection, buffer: Data(), body: body, filename: filename)
            }
            listener.start(queue: queue)
        }
    }

    func stop() { listener.cancel() }

    private static func serve(connection: NWConnection, buffer: Data, body: Data, filename: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            let text = String(decoding: buffer, as: UTF8.self)
            guard text.contains("\r\n\r\n") || isComplete || error != nil else {
                serve(connection: connection, buffer: buffer, body: body, filename: filename)
                return
            }
            let response: Data
            if text.contains("GET /file.txt") {
                let header = """
                    HTTP/1.1 200 OK\r
                    Content-Type: application/octet-stream\r
                    Content-Disposition: attachment; filename="\(filename)"\r
                    Content-Length: \(body.count)\r
                    Connection: close\r
                    \r

                    """
                var payload = Data(header.utf8)
                payload.append(body)
                response = payload
            } else {
                response = Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
            }
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
