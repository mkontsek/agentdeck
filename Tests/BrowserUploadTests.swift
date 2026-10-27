import WebKit
import XCTest

@MainActor
final class BrowserUploadTests: XCTestCase {
    private final class Parameters: WKOpenPanelParameters {
        let multiple: Bool
        let directories: Bool
        init(multiple: Bool, directories: Bool) {
            self.multiple = multiple
            self.directories = directories
        }
        override var allowsMultipleSelection: Bool { multiple }
        override var allowsDirectories: Bool { directories }
    }

    func testUploadPanelFollowsThePageRequest() {
        let single = BrowserController.uploadPanel(
            for: Parameters(multiple: false, directories: false), host: "gemini.google.com")
        XCTAssertTrue(single.canChooseFiles)
        XCTAssertFalse(single.canChooseDirectories)
        XCTAssertFalse(single.allowsMultipleSelection)
        XCTAssertEqual(single.message, "Choose a file to upload to gemini.google.com")

        let many = BrowserController.uploadPanel(for: Parameters(multiple: true, directories: true), host: nil)
        XCTAssertTrue(many.canChooseDirectories)
        XCTAssertTrue(many.allowsMultipleSelection)
        XCTAssertEqual(many.message, "Choose files to upload to this page")
    }
}
