import XCTest
import AppKit

final class ReleaseSmokeTests: XCTestCase {
    @MainActor
    func testCaptureSaveCancelAndToolbar() throws {
        continueAfterFailure = false
        try XCTSkipUnless(NSUserName() == "runner", "Only runs on the isolated hosted runner")
        // Prepared by the workflow outside XCTest's redirected home directory.
        let vault = URL(fileURLWithPath: "/Users/runner/VookReleaseFixture")
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent(".ci-owned").path),
                      "Missing owned fixture at \(vault.path); test container: \(NSHomeDirectory())")
        let app = XCUIApplication(bundleIdentifier: "com.vook4me.app")
        app.activate()
        let add = app.buttons["Add bookmark or memo"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 20), app.debugDescription)

        let viewMenu = app.descendants(matching: .any)["Change view"].firstMatch
        let sortMenu = app.descendants(matching: .any)["Sort bookmarks"].firstMatch
        XCTAssertTrue(viewMenu.exists && sortMenu.exists, app.debugDescription)
        XCTAssertEqual(viewMenu.frame.width, sortMenu.frame.width, accuracy: 0.5)
        XCTAssertEqual(viewMenu.frame.height, sortMenu.frame.height, accuracy: 0.5)
        capture(app, "manager-before")

        // This suite runs only on a fresh hosted VM with a synthetic vault.
        NSPasteboard.general.clearContents()
        let memo = "CI release note 20260909.5"
        add.click()
        let input = app.textFields["Quick add bookmark or note"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10), app.debugDescription)
        input.click()
        input.typeText(memo)
        capture(app, "quick-add-before-save")
        input.typeText("\n")
        XCTAssertTrue(add.waitForExistence(timeout: 15), app.debugDescription)
        let saved = try memoFiles(in: vault)
        XCTAssertEqual(saved.count, 1)
        XCTAssertTrue(try String(contentsOf: saved[0], encoding: .utf8).contains(memo))
        capture(app, "manager-after-save")

        add.click()
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.click()
        input.typeText("Discarded CI draft")
        input.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(add.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(try memoFiles(in: vault).count, 1)
        capture(app, "manager-after-cancel")
    }

    private func memoFiles(in root: URL) throws -> [URL] {
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
        return files.compactMap { $0 as? URL }.filter {
            $0.pathExtension == "md" && !$0.lastPathComponent.hasPrefix(".")
            && !$0.path.contains("/_templates/") && !$0.path.contains("/_trash/")
        }
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
