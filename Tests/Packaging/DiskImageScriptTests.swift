import XCTest

/// Exercises `scripts/make-dmg.sh` with Apple's tools replaced by stubs on `PATH`. Nothing is built, signed,
/// uploaded or mounted, and the real keychain is never consulted.
final class DiskImageScriptTests: XCTestCase {
    private static let developerID = "0123456789ABCDEF0123456789ABCDEF01234567"
    private static let otherDeveloperID = "1123456789ABCDEF0123456789ABCDEF01234567"
    private static let development = "2123456789ABCDEF0123456789ABCDEF01234567"
    private static let developerIDName = "Developer ID Application: Fixture One (AAAAAAAAAA)"
    private static let otherDeveloperIDName = "Developer ID Application: Fixture Two (BBBBBBBBBB)"

    private var directory: URL!
    private var stubs: URL!

    private var script: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts/make-dmg.sh").path
    }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        stubs = directory.appendingPathComponent("stubs")
        try FileManager.default.createDirectory(at: stubs, withIntermediateDirectories: true)
        // A build must never start in these tests. The stub records an attempt and fails it.
        try stub("make", "echo \"$@\" >> '\(directory.path)/make-calls'\nexit 1")
        try keychain(developerIDs: 1)
        try notaryService(profileExists: true, submission: #"{"id":"fixture-submission","status":"Accepted"}"#)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testOneDeveloperIDIdentityIsDetectedAndOtherCertificateKindsAreIgnored() throws {
        let detected = try source("resolve_identity; echo \"identity=$IDENTITY\"")
        XCTAssertEqual(detected.status, 0, detected.output)
        XCTAssertTrue(detected.output.contains("identity=\(Self.developerID)"), detected.output)

        try keychain(developerIDs: 0)
        let missing = try source("resolve_identity")
        XCTAssertEqual(missing.status, 1)
        XCTAssertTrue(missing.output.contains("no \"Developer ID Application\" signing identity"), missing.output)
        XCTAssertTrue(missing.output.contains("make dmg UNSIGNED=1"), missing.output)
    }

    func testSeveralIdentitiesNeedAnExplicitChoiceByNameOrFingerprint() throws {
        try keychain(developerIDs: 2)
        let ambiguous = try source("resolve_identity")
        XCTAssertEqual(ambiguous.status, 1)
        XCTAssertTrue(ambiguous.output.contains("2 \"Developer ID Application\" identities match"), ambiguous.output)
        XCTAssertTrue(ambiguous.output.contains(Self.otherDeveloperIDName), ambiguous.output)

        for choice in [Self.otherDeveloperIDName, Self.otherDeveloperID] {
            let chosen = try source("resolve_identity; echo \"identity=$IDENTITY\"", ["DEVELOPER_ID": choice])
            XCTAssertEqual(chosen.status, 0, chosen.output)
            XCTAssertTrue(chosen.output.contains("identity=\(Self.otherDeveloperID)"), chosen.output)
        }
        // An Apple Development certificate cannot be notarized, even when it is named explicitly.
        for choice in [Self.development, "Apple Development: Fixture (CCCCCCCCCC)", "no such identity"] {
            let rejected = try source("resolve_identity", ["DEVELOPER_ID": choice])
            XCTAssertEqual(rejected.status, 1, choice)
            XCTAssertTrue(rejected.output.contains("DEVELOPER_ID does not name a valid"), rejected.output)
        }
    }

    func testMissingCredentialsAndBadFlagsStopBeforeTheBuild() throws {
        try notaryService(profileExists: false, submission: "{}")
        let noProfile = try execute(["NOTARY_PROFILE": "fixture-profile"])
        XCTAssertEqual(noProfile.status, 1)
        XCTAssertTrue(
            noProfile.output.contains("notarytool cannot use the keychain profile \"fixture-profile\""),
            noProfile.output)
        XCTAssertTrue(noProfile.output.contains("store-credentials fixture-profile"), noProfile.output)

        try keychain(developerIDs: 0)
        let noIdentity = try execute()
        XCTAssertEqual(noIdentity.status, 1)
        XCTAssertTrue(noIdentity.output.contains("no \"Developer ID Application\" signing identity"))

        let badFlag = try execute(["UNSIGNED": "yes"])
        XCTAssertEqual(badFlag.status, 1)
        XCTAssertTrue(badFlag.output.contains("UNSIGNED must be 0 or 1"), badFlag.output)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: directory.appendingPathComponent("make-calls").path),
            "No failed precondition may reach the build")
    }

    func testUnsignedModeNeedsNoCredentialsAndGoesStraightToTheBuild() throws {
        try keychain(developerIDs: 0)
        try notaryService(profileExists: false, submission: "{}")
        let result = try execute(["UNSIGNED": "1"])
        // The stubbed build fails; what matters is that it was the first thing attempted.
        XCTAssertEqual(result.status, 1, result.output)
        XCTAssertFalse(result.output.contains("make-dmg:"), result.output)
        let calls = try String(contentsOf: directory.appendingPathComponent("make-calls"), encoding: .utf8)
        XCTAssertTrue(calls.hasPrefix("build CONFIG=Release"), calls)
    }

    func testNotarizationSucceedsOnlyWhenAppleAcceptsTheSubmission() throws {
        let accepted = try source("notarize \"$FIXTURE/AgentDeck.dmg\"")
        XCTAssertEqual(accepted.status, 0, accepted.output)
        XCTAssertTrue(accepted.output.contains("Accepted: submission fixture-submission"), accepted.output)

        try notaryService(profileExists: true, submission: #"{"id":"fixture-submission","status":"Invalid"}"#)
        let invalid = try source("notarize \"$FIXTURE/AgentDeck.dmg\"; echo unreachable")
        XCTAssertEqual(invalid.status, 1)
        XCTAssertTrue(invalid.output.contains("ended as \"Invalid\" (submission fixture-submission)"), invalid.output)
        XCTAssertTrue(invalid.output.contains("fixture notary log"), "The notary log explains a rejection")
        XCTAssertFalse(invalid.output.contains("unreachable"))

        try notaryService(profileExists: true, submission: "not json")
        let unreadable = try source("notarize \"$FIXTURE/AgentDeck.dmg\"; echo unreachable")
        XCTAssertEqual(unreadable.status, 1)
        XCTAssertTrue(unreadable.output.contains("ended as \"unknown\""), unreadable.output)
    }

    func testNestedCodeIsListedInnermostFirstWithoutTheAppExecutableOrResourceBundles() throws {
        let contents = directory.appendingPathComponent("AgentDeck.app/Contents")
        let framework = contents.appendingPathComponent("Frameworks/Inner.framework")
        let version = framework.appendingPathComponent("Versions/A")
        let helper = version.appendingPathComponent("Helpers/tool")
        let library = contents.appendingPathComponent("Frameworks/libfixture.dylib")
        let resources = contents.appendingPathComponent("Resources/Assets.bundle")
        let manager = FileManager.default
        for folder in [contents.appendingPathComponent("MacOS"), helper.deletingLastPathComponent(), resources] {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let machO = URL(fileURLWithPath: "/usr/bin/true")
        let binary = version.appendingPathComponent("Inner")
        for code in [contents.appendingPathComponent("MacOS/AgentDeck"), binary, helper, library] {
            try manager.copyItem(at: machO, to: code)
        }
        try Data("fixture".utf8).write(to: resources.appendingPathComponent("data.txt"))
        try manager.createSymbolicLink(
            atPath: framework.appendingPathComponent("Inner").path, withDestinationPath: "Versions/A/Inner")

        let result = try source("nested_code \"$FIXTURE/AgentDeck.app\" | tr '\\0' '\\n'")
        XCTAssertEqual(result.status, 0, result.output)
        let listed = result.output.split(separator: "\n").map {
            // The script sees the same tree through the unresolved temporary path.
            String($0).replacingOccurrences(of: directory.path + "/", with: "")
        }
        let prefix = "AgentDeck.app/Contents/Frameworks/"
        XCTAssertEqual(
            Set(listed),
            [
                prefix + "Inner.framework/Versions/A/Helpers/tool", prefix + "Inner.framework/Versions/A/Inner",
                prefix + "Inner.framework", prefix + "libfixture.dylib",
            ], result.output)
        let bundle = try XCTUnwrap(listed.firstIndex(of: prefix + "Inner.framework"))
        XCTAssertLessThan(
            try XCTUnwrap(listed.firstIndex(of: prefix + "Inner.framework/Versions/A/Helpers/tool")), bundle)
        XCTAssertLessThan(try XCTUnwrap(listed.firstIndex(of: prefix + "Inner.framework/Versions/A/Inner")), bundle)
    }

    // MARK: Fixture

    /// Writes a `security` stub listing `developerIDs` Developer ID identities and one Apple Development identity.
    private func keychain(developerIDs: Int) throws {
        var lines: [String] = []
        if developerIDs > 0 { lines.append("  1) \(Self.developerID) \"\(Self.developerIDName)\"") }
        if developerIDs > 1 { lines.append("  2) \(Self.otherDeveloperID) \"\(Self.otherDeveloperIDName)\"") }
        lines.append("  3) \(Self.development) \"Apple Development: Fixture (CCCCCCCCCC)\"")
        lines.append("     \(lines.count) valid identities found")
        try stub("security", "cat <<'IDENTITIES'\n\(lines.joined(separator: "\n"))\nIDENTITIES")
    }

    /// Writes an `xcrun` stub that answers `notarytool` itself and fails anything else, so no real tool runs.
    private func notaryService(profileExists: Bool, submission: String) throws {
        try stub(
            "xcrun",
            """
            [ "$1" = notarytool ] || { echo "unexpected xcrun $*" >&2; exit 64; }
            case $2 in
            history) exit \(profileExists ? 0 : 69) ;;
            submit) cat <<'RESULT'
            \(submission)
            RESULT
            ;;
            log) echo "fixture notary log" ;;
            *) exit 64 ;;
            esac
            """)
    }

    private func stub(_ name: String, _ body: String) throws {
        let url = stubs.appendingPathComponent(name)
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    /// Sources the script for its functions, then runs `commands`.
    private func source(_ commands: String, _ environment: [String: String] = [:]) throws -> (
        status: Int32, output: String
    ) {
        try run(["-c", "source \"$SCRIPT\"; \(commands)"], environment)
    }

    /// Runs the script itself, as `make dmg` does.
    private func execute(_ environment: [String: String] = [:]) throws -> (status: Int32, output: String) {
        try run([script], environment)
    }

    private func run(_ arguments: [String], _ environment: [String: String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = [
            "PATH": "\(stubs.path):/usr/bin:/bin:/usr/sbin:/sbin", "SCRIPT": script, "FIXTURE": directory.path,
            "DERIVED": directory.appendingPathComponent("derived").path, "TMPDIR": directory.path,
        ].merging(environment) { $1 }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
