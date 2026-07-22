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
        XCTAssertTrue(app.staticTexts["projects.card.title.project-1"].exists)
        XCTAssertTrue(app.staticTexts["projects.card.scanCount.project-1"].exists)
        XCTAssertTrue(app.buttons["projects.card.menu.project-1"].exists)
        XCTAssertTrue(app.buttons["projects.scan.project-1-scan-1"].exists)
        XCTAssertTrue(app.staticTexts["projects.scan.status.uploading"].exists)

        app.tabBars.buttons["Account"].tap()
        XCTAssertTrue(app.buttons["account.signOut"].waitForExistence(timeout: 5))
        app.buttons["account.signOut"].tap()

        XCTAssertTrue(app.staticTexts["auth.title"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.tabBars.buttons["Projects"].isSelected)
    }

    @MainActor
    func testPullToRefreshCollapsesExpandedProjectCards() throws {
        let app = launchApp(arguments: ["-UITesting", "-UITestSignedIn"])

        XCTAssertTrue(app.scrollViews["projects.list"].waitForExistence(timeout: 5))
        app.buttons["projects.card.expand.project-2"].tap()
        XCTAssertTrue(app.buttons["projects.scan.project-2-scan-4"].waitForExistence(timeout: 2))

        app.scrollViews["projects.list"].swipeDown()

        XCTAssertFalse(app.buttons["projects.scan.project-2-scan-4"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testEmptyProjectsStateShowsRequiredMessage() throws {
        let app = launchApp(arguments: ["-UITesting", "-UITestSignedIn", "-UITestProjectsEmpty"])

        XCTAssertTrue(app.staticTexts["No projects yet. Create your first project and start scanning."].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPaginationFailureShowsRetryToast() throws {
        let app = launchApp(arguments: ["-UITesting", "-UITestSignedIn", "-UITestProjectsNextPageFails"])

        XCTAssertTrue(app.scrollViews["projects.list"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.swipeUp()

        XCTAssertTrue(app.staticTexts["Network error. Unable to load more projects."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["projects.pagination.retry"].exists)
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
