import XCTest

final class ShellUITests: XCTestCase {
    @MainActor
    func testOfflineWritingAndKeyboardUndo() throws {
        let app = XCUIApplication()
        app.launchEnvironment["NW_TEST_DEFAULTS"] = "com.mariusschober.nostrwriter.tests.\(UUID())"
        app.launchArguments = ["-recordingChoice", "off"]
        app.launch()
        let editor = app.textViews["markdown-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        // First launch must accept typing immediately, without a click that
        // would mask an incorrect initial responder in the sidebar.
        editor.typeText("Synthetic writing fixture.")
        XCTAssertEqual(editor.value as? String, "Synthetic writing fixture.")
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText("Replacement")
        editor.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(editor.value as? String, "Synthetic writing fixture.")
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "Stage 01 writing shell"; attachment.lifetime = .keepAlways
        add(attachment)
        app.terminate()
    }

    @MainActor
    func testFirstLaunchConsentAndKeyboardEscape() throws {
        let app = XCUIApplication()
        app.launchEnvironment["NW_TEST_DEFAULTS"] = "com.mariusschober.nostrwriter.tests.\(UUID())"
        app.launch()
        let decline = app.buttons["Write Without Recording"]
        XCTAssertTrue(decline.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Start Writing with Recording"].exists)
        XCTAssertTrue(app.buttons["Learn About Proof"].exists)
        let consent = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        consent.name = "First launch recording consent"; consent.lifetime = .keepAlways
        add(consent)
        app.typeKey(.escape, modifierFlags: [])
        let editor = app.textViews["markdown-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("Writing without history.")
        XCTAssertEqual(editor.value as? String, "Writing without history.")
        XCTAssertTrue(app.staticTexts["Recording off"].exists)
        app.terminate()
    }

    @MainActor
    func testShellAppearanceAndWindowSizes() throws {
        for (appearance, size) in [("light", "regular"), ("dark", "regular"), ("light", "narrow"), ("dark", "narrow")] {
            let app = XCUIApplication()
            app.launchArguments = ["-recordingChoice", "off"]
            app.launchEnvironment["NW_TEST_DEFAULTS"] = "com.mariusschober.nostrwriter.tests.\(UUID())"
            app.launchEnvironment["NW_TEST_APPEARANCE"] = appearance
            app.launchEnvironment["NW_TEST_WINDOW_SIZE"] = size
            app.launch()
            let editor = app.textViews["markdown-editor"]
            XCTAssertTrue(editor.waitForExistence(timeout: 10))
            editor.click(); editor.typeText("# A quiet place to write\n\nSynthetic interface fixture. Writing stays available without an account.")
            let frame = app.windows.firstMatch.frame
            XCTAssertEqual(frame.width, size == "narrow" ? 760 : 1120, accuracy: 1)
            XCTAssertEqual(frame.height, size == "narrow" ? 520 : 760, accuracy: 1)
            let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            attachment.name = "shell-\(appearance)-\(size)"; attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }
}
