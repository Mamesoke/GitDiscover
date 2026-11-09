//
//  GitDiscoverUITests.swift
//  GitDiscoverUITests
//
//  Created by Kevin MENENDEZ on 09/11/2026.
//

import XCTest

final class GitDiscoverUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testSearchDetailAndClear() {
        let app = launchApp()
        search("swift", in: app)
        let row = app.buttons["repository-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        capture(app, name: "Search results")
        row.tap()
        XCTAssertTrue(app.staticTexts["owner-value"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["owner-value"].label, "Owner, apple")
        XCTAssertEqual(app.staticTexts["language-value"].label, "Language, Swift")
        XCTAssertTrue(app.staticTexts["stars-value"].exists)
        XCTAssertTrue(app.staticTexts["forks-value"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["github-link"].exists)
        capture(app, name: "Repository detail")
        app.navigationBars.buttons["GitDiscover"].tap()
        app.buttons["clear-search"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["idle-title"].waitForExistence(timeout: 5))
        XCTAssertFalse(row.exists)
    }

    @MainActor
    func testMissingFieldsHaveDetailFallbacks() {
        let app = launchApp()
        search("swift", in: app)
        let row = app.buttons["repository-2"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.staticTexts["description-value"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["description-value"].label, "No description provided")
        XCTAssertEqual(app.staticTexts["language-value"].label, "Language, Unknown language")
    }

    @MainActor
    func testEmptySearchState() {
        let app = launchApp()
        search("empty", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["empty-state"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["repository-1"].exists)
    }

    @MainActor
    func testRecoverableFailureCanBeRetried() {
        let app = launchApp()
        search("offline", in: app)
        let retry = app.buttons["retry-search"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertTrue(retry.isEnabled)
        retry.tap()
        XCTAssertTrue(app.buttons["repository-1"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testRateLimitDisablesImmediateRetry() {
        let app = launchApp()
        search("ratelimit", in: app)
        let retry = app.buttons["retry-search"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertFalse(retry.isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["error-state"].exists)
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func search(_ query: String, in app: XCUIApplication) {
        let field = app.textFields["search-field"]
        field.tap()
        field.typeText(query)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
