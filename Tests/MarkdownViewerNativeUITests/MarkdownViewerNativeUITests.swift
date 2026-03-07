import XCTest

@MainActor
final class MarkdownViewerNativeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIApplication(bundleIdentifier: "com.meik.MarkdownViewerNative").terminate()
    }

    override func tearDownWithError() throws {
        XCUIApplication(bundleIdentifier: "com.meik.MarkdownViewerNative").terminate()
    }

    func testOpenToolbarLoadsFixtureSource() throws {
        let app = makeApp(openFixtureOnDemand: true)

        app.launch()

        let openButton = app.buttons["toolbar.open"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 5))
        openButton.click()

        XCTAssertTrue(app.staticTexts["Library"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["notes.md"].waitForExistence(timeout: 5))
    }

    func testSidebarAndInspectorCanBeToggled() throws {
        let app = makeApp(preloadFixture: true)

        app.launch()

        XCTAssertTrue(app.staticTexts["Library"].waitForExistence(timeout: 5))

        app.typeKey("s", modifierFlags: [.command, .option])
        XCTAssertFalse(app.staticTexts["Library"].waitForExistence(timeout: 2))

        app.typeKey("s", modifierFlags: [.command, .option])
        XCTAssertTrue(app.staticTexts["Library"].waitForExistence(timeout: 5))

        let inspectorButton = app.buttons["toolbar.inspector"]
        XCTAssertTrue(inspectorButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Overview"].waitForExistence(timeout: 5))

        inspectorButton.click()
        XCTAssertFalse(app.staticTexts["Overview"].waitForExistence(timeout: 2))

        inspectorButton.click()
        XCTAssertTrue(app.staticTexts["Overview"].waitForExistence(timeout: 5))
    }

    func testOutlineAndZoomCommandsSmoke() throws {
        let app = makeApp(preloadFixture: true)

        app.launch()

        XCTAssertTrue(app.staticTexts["notes.md"].waitForExistence(timeout: 5))
        app.staticTexts["notes.md"].click()

        let outlineItem = app.staticTexts["Details"]
        XCTAssertTrue(outlineItem.waitForExistence(timeout: 5))
        outlineItem.click()

        app.typeKey("=", modifierFlags: [.command])
        app.typeKey("-", modifierFlags: [.command])
        app.typeKey("0", modifierFlags: [.command])

        XCTAssertTrue(app.webViews["detail.webPreview"].waitForExistence(timeout: 5))
    }

    private func makeApp(preloadFixture: Bool = false, openFixtureOnDemand: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        let fixtureRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Library", isDirectory: true)

        app.launchEnvironment["MARKDOWN_VIEWER_UI_TESTING"] = "1"

        if preloadFixture {
            app.launchEnvironment["MARKDOWN_VIEWER_UI_TEST_FIXTURE_ROOT"] = fixtureRoot.path
        }

        if openFixtureOnDemand {
            app.launchEnvironment["MARKDOWN_VIEWER_UI_TEST_OPEN_ROOT"] = fixtureRoot.path
        }

        return app
    }
}
