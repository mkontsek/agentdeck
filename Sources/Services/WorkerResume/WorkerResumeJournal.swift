import Foundation

/// A separate atomic journal prevents an older running host from erasing request identities.
@MainActor
final class WorkerResumeJournal {
    let url: URL
    private(set) var requests: [WorkerResumeRequest] = []
    private(set) var error: String?

    init(url: URL) {
        self.url = url
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            guard let data = try handle.read(upToCount: 8_388_609), data.count <= 8_388_608 else {
                throw CoordinationError(message: "Resume journal is too large.")
            }
            requests = try JSONDecoder().decode([WorkerResumeRequest].self, from: data)
            guard requests.count <= 1024, Set(requests.map(\.id)).count == requests.count else {
                throw CoordinationError(
                    message: "Resume journal has duplicate identities or exceeds its request limit.")
            }
            for index in requests.indices where requests[index].phase.reservesWorker {
                requests[index].phase = .uncertain
                requests[index].detail =
                    "Host restarted during this request. Never replay automatically; verify the provider before continuing."
            }
            try persist(requests)
        } catch {
            requests = []
            self.error = "Resume journal unavailable; original preserved: \(error.localizedDescription)"
        }
    }

    func put(_ request: WorkerResumeRequest) throws {
        if let error { throw CoordinationError(message: error) }
        var next = requests
        if let index = next.firstIndex(where: { $0.id == request.id }) {
            next[index] = request
        } else {
            guard next.count < 1024 else {
                throw CoordinationError(message: "Resume request journal is full; retain it for retry safety.")
            }
            next.append(request)
        }
        try persist(next)
        requests = next
    }

    private func persist(_ next: [WorkerResumeRequest]) throws {
        let data = try JSONEncoder().encode(next)
        guard data.count <= 8_388_608 else { throw CoordinationError(message: "Resume journal is full.") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
