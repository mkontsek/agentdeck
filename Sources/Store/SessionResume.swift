import Foundation

extension AppStore {
    func resumeCheckpoint(for session: ManagedSession) -> SessionResumeCheckpoint? {
        guard let checkpoint = resumeCheckpoints[session.id],
            checkpoint.matches(
                profileID: session.cliProfileID ?? "", directory: session.effectiveDirectory.expandingTilde)
        else { return nil }
        return checkpoint
    }

    func recordSessionLaunch(_ session: ManagedSession, resuming: Bool) {
        var checkpoint =
            resumeCheckpoint(for: session)
            ?? SessionResumeCheckpoint(
                profileID: session.cliProfileID ?? "", directory: session.effectiveDirectory.expandingTilde,
                launchedAt: Date())
        checkpoint.launchedAt = Date()
        if !resuming {
            checkpoint.conversationID = nil
            checkpoint.conversationPath = nil
        }
        saveResumeCheckpoint(checkpoint, for: session.id)
    }

    func saveResumeCheckpoint(_ checkpoint: SessionResumeCheckpoint, for id: UUID) {
        guard resumeCheckpoints[id] != checkpoint else { return }
        resumeCheckpoints[id] = checkpoint
        do {
            try ResumeCheckpointStorage.write(checkpoint, id: id, directory: resumeDirectory)
        } catch {
            lastError = "Could not save session resume information: \(error.localizedDescription)"
        }
    }

    func startResumeTracking() {
        guard resumeTrackingTask == nil else { return }
        resumeTrackingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await captureConversations()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }

    func prepareSessionRestoration() async {
        let tracking = resumeTrackingTask
        resumeTrackingTask = nil
        tracking?.cancel()
        await tracking?.value
        await captureConversations()
        for index in sessions.indices where sessions[index].kind == .browser {
            if let url = browsers.controllers[sessions[index].id]?.webView.url?.absoluteString {
                sessions[index].url = url
            }
        }
        saveNow()
    }

    /// Called periodically and awaited before normal termination, while the provider processes still exist.
    func captureConversations() async {
        guard !resumeCaptureInProgress else { return }
        resumeCaptureInProgress = true
        defer { resumeCaptureInProgress = false }
        let candidates = sessions.compactMap { session -> ConversationCapture? in
            guard session.kind == .cli, runtime[session.id]?.isRunning == true,
                let profileID = session.cliProfileID, ["claude", "codex", "grok"].contains(profileID),
                let pid = terminals.view(for: session.id)?.process?.shellPid, pid > 0
            else { return nil }
            return ConversationCapture(
                id: session.id, profileID: profileID, directory: session.effectiveDirectory.expandingTilde,
                pid: pid, generation: runtime[session.id]?.generation ?? 0)
        }
        let worker = Task.detached(priority: .utility) {
            candidates.compactMap { candidate -> (ConversationCapture, SessionResumeCheckpoint)? in
                guard !Task.isCancelled,
                    let checkpoint = ProcessConversationReader.read(
                        profileID: candidate.profileID, directory: candidate.directory, pid: candidate.pid)
                else { return nil }
                return (candidate, checkpoint)
            }
        }
        let captured = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard !Task.isCancelled else { return }
        for (candidate, found) in captured {
            guard let session = session(candidate.id), runtime[candidate.id]?.generation == candidate.generation,
                runtime[candidate.id]?.isRunning == true,
                found.matches(
                    profileID: session.cliProfileID ?? "", directory: session.effectiveDirectory.expandingTilde)
            else { continue }
            var checkpoint = found
            checkpoint.launchedAt = resumeCheckpoints[candidate.id]?.launchedAt ?? found.launchedAt
            saveResumeCheckpoint(checkpoint, for: candidate.id)
        }
    }
}

private struct ConversationCapture: Sendable {
    let id: UUID
    let profileID: String
    let directory: String
    let pid: Int32
    let generation: Int
}
