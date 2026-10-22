import XCTest

final class SkillLibraryTests: XCTestCase {
    private func writeSkill(_ root: URL, name: String = "sample", summary: String = "Useful workflow") throws -> URL {
        let directory = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("SKILL.md")
        try Data("---\nname: \(name)\ndescription: \(summary)\n---\nRead references/example.md before editing.\n".utf8)
            .write(to: file)
        return file
    }

    func testRepositoryRootsSymlinksAndDuplicateDirectories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let skills = root.appendingPathComponent(".agents/skills")
        let first = try writeSkill(skills)
        let second = try writeSkill(skills, name: "second")
        try FileManager.default.createSymbolicLink(
            at: skills.appendingPathComponent("alias"), withDestinationURL: first.deletingLastPathComponent())
        try FileManager.default.createSymbolicLink(
            at: skills.appendingPathComponent("loop"), withDestinationURL: skills)
        _ = try writeSkill(root.appendingPathComponent("node_modules"), name: "ignored")
        let scan = SkillScanner.scan(directories: [root.path, skills.path, first.deletingLastPathComponent().path])
        XCTAssertEqual(Set(scan.skills.map(\.path)), Set([first.path, second.path]))
        XCTAssertTrue(scan.warnings.isEmpty)
    }

    func testMetadataFoldedDescriptionAndQuotedNames() {
        let metadata = SkillScanner.metadata(
            in: """
                ---
                name: 'reviewer''s-helper'
                description: >-
                  Review Swift
                  and its tests.
                metadata:
                  name: ignored
                ---
                # Body
                """)
        XCTAssertEqual(metadata["name"], "reviewer's-helper")
        XCTAssertEqual(metadata["description"], "Review Swift and its tests.")
        XCTAssertTrue(SkillScanner.metadata(in: "# No frontmatter").isEmpty)
    }

    func testMissingAndOversizedSkillsReportWarnings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try writeSkill(root)
        try Data(repeating: 65, count: SkillScanner.maximumFileBytes + 1).write(to: file)
        let scan = SkillScanner.scan(directories: [root.path, root.appendingPathComponent("missing").path])
        XCTAssertTrue(scan.skills.isEmpty)
        XCTAssertEqual(scan.warnings.count, 2)
    }

    @MainActor
    func testEnabledCatalogMCPAndRemovingDirectories() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: root)
        }
        let skill = try writeSkill(root.appendingPathComponent("skills"))
        let hidden = try writeSkill(root.appendingPathComponent("skills"), name: "hidden")
        store.settings.skillDirectories = [root.appendingPathComponent("skills").path]
        store.settings.disabledSkillIDs = [hidden.path]
        await store.skillLibrary.waitUntilLoaded()
        XCTAssertEqual(store.skillLibrary.enabledSkills.map(\.path), [skill.path])
        let catalog = try String(contentsOf: store.skillsCatalogURL, encoding: .utf8)
        XCTAssertTrue(catalog.contains(skill.path))
        XCTAssertFalse(catalog.contains(hidden.path))
        let session = store.addSession(ManagedSession(name: "Reader", kind: .cli), start: false)
        XCTAssertFalse(store.callTool(name: "read_skill", args: ["skill_id": skill.path], caller: session.id).isError)
        XCTAssertTrue(store.callTool(name: "read_skill", args: ["skill_id": hidden.path], caller: session.id).isError)
        XCTAssertTrue(store.callTool(name: "read_skill", args: ["skill_id": "/etc/passwd"], caller: session.id).isError)
        XCTAssertEqual(store.environment(for: session)["AGENTDECK_SKILLS_FILE"], store.skillsCatalogURL.path)
        store.settings.skillDirectories = []
        await store.skillLibrary.waitUntilLoaded()
        XCTAssertTrue(store.skillLibrary.enabledSkills.isEmpty)
        XCTAssertFalse(try String(contentsOf: store.skillsCatalogURL, encoding: .utf8).contains(skill.path))
        XCTAssertTrue(store.callTool(name: "read_skill", args: ["skill_id": skill.path], caller: session.id).isError)
    }

    @MainActor
    func testLatestReloadWins() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try writeSkill(root.appendingPathComponent("old"))
        let library = SkillLibrary()
        let catalog = root.appendingPathComponent("catalog.md")
        library.reload(directories: [root.appendingPathComponent("old").path], disabledIDs: [], catalogURL: catalog)
        library.reload(directories: [], disabledIDs: [], catalogURL: catalog)
        await library.waitUntilLoaded()
        XCTAssertTrue(library.skills.isEmpty)
        XCTAssertFalse(try String(contentsOf: catalog, encoding: .utf8).contains("sample"))
    }
}
