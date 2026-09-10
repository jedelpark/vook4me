import XCTest
import AppKit
import Carbon

final class ReleaseSmokeTests: XCTestCase {
    @MainActor
    func testCaptureSaveCancelAndToolbar() async throws {
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
        let memo = "CI release verification memo"
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

        try await restartManager(app)
        XCTAssertEqual(try memoFiles(in: vault).count, 1)
        let restored = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", memo)).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 10), app.debugDescription)
        capture(app, "manager-after-relaunch")
    }

    @MainActor
    func testIMECompositionEscape() throws {
        continueAfterFailure = false
        try XCTSkipUnless(NSUserName() == "runner", "Only runs on the isolated hosted runner")
        let app = XCUIApplication(bundleIdentifier: "com.vook4me.app")
        app.activate()
        let add = app.buttons["Add bookmark or memo"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 15), app.debugDescription)
        add.click()
        let input = app.textFields["Quick add bookmark or note"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.click()
        let previous = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        defer { TISSelectInputSource(previous) }
        // TextInputSources.h requires enabling the parent method before an input mode.
        let methods = TISCreateInputSourceList([kTISPropertyInputSourceID as String: "com.apple.inputmethod.Korean"] as CFDictionary, true).takeRetainedValue() as! [TISInputSource]
        XCTAssertEqual(TISEnableInputSource(try XCTUnwrap(methods.first)), noErr)
        let sources = TISCreateInputSourceList([kTISPropertyInputSourceID as String: "com.apple.inputmethod.Korean.2SetKorean"] as CFDictionary, true).takeRetainedValue() as! [TISInputSource]
        let korean = try XCTUnwrap(sources.first, "Built-in Korean input source is required")
        XCTAssertEqual(TISEnableInputSource(korean), noErr)
        XCTAssertEqual(TISSelectInputSource(korean), noErr)
        // Switch the active app's source through the system shortcut if the first source was not applied there.
        for attempt in 0..<3 {
            if attempt > 0 {
                input.typeKey("a", modifierFlags: [.command])
                input.typeKey(.delete, modifierFlags: [])
                input.typeKey(" ", modifierFlags: [.control, .option])
            }
            for key in ["r", "k", "s"] {
                input.typeKey(XCUIKeyboardKey(rawValue: key), modifierFlags: [])
            }
            if input.value as? String == "간" { break }
        }
        capture(app, "ime-input-observed")
        let composed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "간"), object: input)
        XCTAssertEqual(XCTWaiter.wait(for: [composed], timeout: 5), .completed, input.debugDescription)
        capture(app, "ime-composing")
        input.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(input.waitForExistence(timeout: 3), "First Escape must finish/cancel composition without closing Quick Add")
        capture(app, "ime-after-first-escape")
        input.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(add.waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor
    func testKeyboardCapture() async throws {
        continueAfterFailure = false
        try XCTSkipUnless(NSUserName() == "runner", "Only runs on the isolated hosted runner")
        let app = XCUIApplication(bundleIdentifier: "com.vook4me.app")
        try await restartManager(app)
        let vault = URL(fileURLWithPath: "/Users/runner/VookReleaseFixture")
        let before = try memoFiles(in: vault).count
        app.typeKey(",", modifierFlags: [.command, .option])
        let input = app.textFields["Quick add bookmark or note"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10), app.debugDescription)
        input.typeText("CI keyboard capture\n")
        XCTAssertTrue(app.buttons["Add bookmark or memo"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(try memoFiles(in: vault).count, before + 1)
        capture(app, "keyboard-capture-saved")
    }

    @MainActor
    func testVoiceOverNavigation() async throws {
        continueAfterFailure = false
        try XCTSkipUnless(NSUserName() == "runner", "Only runs on the isolated hosted runner")
        let app = XCUIApplication(bundleIdentifier: "com.vook4me.app")
        try await restartManager(app)
        app.typeKey("h", modifierFlags: [.command])
        _ = try await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Library/CoreServices/VoiceOver.app"), configuration: .init())
        let voiceOver = XCUIApplication(bundleIdentifier: "com.apple.VoiceOver")
        let use = voiceOver.buttons["Use VoiceOver"].firstMatch
        if use.waitForExistence(timeout: 8) { use.click() }
        let f5 = XCUIKeyboardKey.F5
        let f10 = XCUIKeyboardKey.F10
        defer {
            if NSWorkspace.shared.isVoiceOverEnabled {
                app.typeKey(f5, modifierFlags: [.command])
            }
        }
        captureDesktop("voiceover-started")
        XCTAssertTrue(NSWorkspace.shared.isVoiceOverEnabled)
        app.activate()
        // Caption visibility is a toggle; both states are captured to avoid assuming the image default.
        for phase in 0..<2 {
            app.typeKey(f10, modifierFlags: [.control, .option, .command])
            for step in 0..<3 {
                app.typeKey(.rightArrow, modifierFlags: [.control, .option])
                try await Task.sleep(nanoseconds: 500_000_000)
                captureDesktop("voiceover-navigation-\(phase)-\(step)")
            }
        }
        app.typeKey("u", modifierFlags: [.control, .option])
        captureDesktop("voiceover-rotor-request")
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("i", modifierFlags: [.control, .option])
        captureDesktop("voiceover-item-chooser-request")
        // Speech/caption and rotor behavior require inspection of these actual captures.
    }

    private func memoFiles(in root: URL) throws -> [URL] {
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
        return files.compactMap { $0 as? URL }.filter {
            $0.pathExtension == "md" && !$0.lastPathComponent.hasPrefix(".")
            && !$0.path.contains("/_templates/") && !$0.path.contains("/_trash/")
        }
    }

    @MainActor
    private func restartManager(_ app: XCUIApplication) async throws {
        let url = try XCTUnwrap(NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.vook4me.app"))
        app.terminate()
        app.launch()
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: .init())
        XCTAssertTrue(app.buttons["Add bookmark or memo"].waitForExistence(timeout: 15), app.debugDescription)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func captureDesktop(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
