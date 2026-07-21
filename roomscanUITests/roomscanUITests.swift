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
    func testMockSignInReachesHomeAndSignOutReturns() throws {
        let app = launchApp(arguments: ["-UITesting"])

        XCTAssertTrue(app.buttons["auth.signInWithApple"].waitForExistence(timeout: 5))
        app.buttons["auth.signInWithApple"].tap()

        XCTAssertTrue(app.buttons["home.signOut"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["home.welcome"].exists)
        app.buttons["home.signOut"].tap()

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
    func testPersistedSessionLaunchOpensHome() throws {
        let app = launchApp(arguments: ["-UITesting", "-UITestSignedIn"])

        XCTAssertTrue(app.buttons["home.signOut"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["home.welcome"].exists)
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
