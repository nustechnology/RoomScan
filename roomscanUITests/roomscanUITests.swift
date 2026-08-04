//
//  roomscanUITests.swift
//  roomscanUITests
//

import XCTest

final class roomscanUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSignedOutLaunchShowsAuthentication() throws {
        let app = launchApp(arguments: ["-UITesting"])

        XCTAssertTrue(app.staticTexts["auth.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["auth.signInWithApple"].exists)
    }

    @MainActor
    func testMockSignInReachesProjectsAndSignOutReturns() throws {
        let app = launchApp(arguments: ["-UITesting"])

        XCTAssertTrue(app.buttons["auth.signInWithApple"].waitForExistence(timeout: 5))
        app.buttons["auth.signInWithApple"].tap()

        XCTAssertTrue(app.scrollViews["projects.list"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["projects.card.title.project-1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["projects.card.scanCount.project-1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["projects.card.menu.project-1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["projects.scan.project-1-scan-1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["projects.scan.status.uploading"].waitForExistence(timeout: 5))

        app.buttons["tab.account"].tap()
        XCTAssertTrue(app.buttons["account.signOut"].waitForExistence(timeout: 5))
        app.buttons["account.signOut"].tap()
        XCTAssertTrue(app.alerts["Sign Out?"].waitForExistence(timeout: 5))
        app.alerts["Sign Out?"].buttons["Sign Out"].tap()

        XCTAssertTrue(app.staticTexts["auth.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["app.toast"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPrivacyPolicyNavigation() throws {
        let app = launchApp(arguments: ["-UITesting"])

        XCTAssertTrue(app.buttons["auth.privacy"].waitForExistence(timeout: 5))
        app.buttons["auth.privacy"].tap()

        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 5))
    }

    @MainActor
    func testPersistedSessionLaunchOpensProjectsTab() throws {
        let app = launchApp(arguments: ["-UITesting", "-UITestSignedIn"])

        XCTAssertTrue(app.scrollViews["projects.list"].waitForExistence(timeout: 5))
        let projectsTab = app.buttons["tab.projects"]
        XCTAssertTrue(projectsTab.waitForExistence(timeout: 5))
        XCTAssertTrue(projectsTab.isSelected)
    }

    @MainActor
    func testEmptyProjectsStateShowsRequiredMessage() throws {
        let app = launchApp(arguments: ["-UITesting", "-UITestSignedIn", "-UITestProjectsEmpty"])

        XCTAssertTrue(app.staticTexts["projects.emptyState"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSavingNewProjectOpensEmptyProjectDetail() throws {
        let app = launchApp(arguments: ["-UITesting", "-UITestSignedIn"])

        XCTAssertTrue(app.buttons["projects.create"].waitForExistence(timeout: 5))
        app.buttons["projects.create"].tap()

        let nameField = app.textFields["projects.newProject.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Client Walkthrough")
        app.buttons["projects.newProject.save"].tap()

        XCTAssertTrue(app.buttons["projects.detail.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Client Walkthrough"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["projects.detail.emptyScans"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["projects.detail.addScan"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["projects.detail.shareProject"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRestoreFailureShowsRetry() throws {
        let app = launchApp(arguments: ["-UITesting", "-UITestRestoreFails"])

        XCTAssertTrue(app.buttons["app.restoreRetry"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func launchApp(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }
}
