import Foundation

struct CleanupError: Error, CustomStringConvertible {
    let description: String
}

func cleanupInstallations(installed: URL, buildDirectory: URL) throws {
    let manager = FileManager.default
    let bundleID = "io.kontsek.agentdeck"
    guard let bundle = Bundle(url: installed), bundle.bundleIdentifier == bundleID,
        let installedVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    else { throw CleanupError(description: "No verified AgentDeck installation at \(installed.path)") }

    var scanError: Error?
    guard
        let scan = manager.enumerator(
            at: buildDirectory, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, error in
                scanError = error
                return false
            })
    else { throw CleanupError(description: "Could not scan \(buildDirectory.path)") }

    var duplicates: [URL] = []
    for case let candidate as URL in scan where candidate.pathExtension == "app" {
        guard candidate.resolvingSymlinksInPath() != installed.resolvingSymlinksInPath(),
            let copy = Bundle(url: candidate), copy.bundleIdentifier == bundleID
        else { continue }
        guard let version = copy.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            throw CleanupError(description: "Could not determine the version at \(candidate.path)")
        }
        guard version.compare(installedVersion, options: .numeric) != .orderedDescending else {
            throw CleanupError(description: "Install the newer \(version) build at \(candidate.path) before cleanup")
        }
        duplicates.append(candidate)
    }
    if let scanError { throw scanError }

    for duplicate in duplicates {
        var trashed: NSURL?
        try manager.trashItem(at: duplicate, resultingItemURL: &trashed)
        if let path = trashed?.path {
            let unregister = Process()
            unregister.executableURL = URL(
                fileURLWithPath:
                    "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
            )
            unregister.arguments = ["-u", path]
            try unregister.run()
            unregister.waitUntilExit()
            guard unregister.terminationStatus == 0 else {
                throw CleanupError(description: "Moved \(duplicate.path) to Trash, but could not unregister it")
            }
        }
        print("Moved duplicate to Trash: \(duplicate.path)")
    }
    print("Kept AgentDeck \(installedVersion) at \(installed.path); removed \(duplicates.count) duplicate(s)")
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw CleanupError(description: "Usage: cleanup-installations.swift <installed app> <build directory>")
    }
    try cleanupInstallations(
        installed: URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL,
        buildDirectory: URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL)
} catch {
    FileHandle.standardError.write(Data("AgentDeck cleanup failed: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}
