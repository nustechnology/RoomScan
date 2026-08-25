//
//  ScanningUITests.swift
//  roomscanUITests
//

import XCTest

final class ScanningUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testNewScanFromMyProjects_completesFlow() throws {
        let app = launchApp(arguments: ["-UITesting", "-UITestSignedIn"])

        XCTAssertTrue(app.scrollViews["projects.list"].waitForExistence(timeout: 5))

        // Tap "+ New Scan"
        let newScanButton = app.buttons["home.newScan"]
        XCTAssertTrue(newScanButton.waitForExistence(timeout: 5))
        newScanButton.tap()

        // Tap "Start Scan" on Scan Check screen
        let startScanButton = app.buttons["scancheck.startScan"]
        XCTAssertTrue(startScanButton.waitForExistence(timeout: 5))
        let startEnabledPredicate = NSPredicate(format: "isEnabled == true")
        expectation(for: startEnabledPredicate, evaluatedWith: startScanButton, handler: nil)
        waitForExpectations(timeout: 5)
        startScanButton.tap()

        // Verify Camera Scan View opens & finish button becomes enabled
        let finishButton = app.buttons["scanning.finishButton"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 5))
        let isEnabledPredicate = NSPredicate(format: "isEnabled == true")
        expectation(for: isEnabledPredicate, evaluatedWith: finishButton, handler: nil)
        waitForExpectations(timeout: 5)

        // Tap Finish
        finishButton.tap()

        // Verify Review Scan View opens
        let saveButton = app.buttons["review.saveButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))

        let scanNameField = app.textFields["review.scanNameField"]
        if scanNameField.waitForExistence(timeout: 3) {
            scanNameField.tap()
            scanNameField.typeText(" Scan Alpha")
        }

        let projectDropdown = app.buttons["review.selectProjectDropdown"]
        XCTAssertTrue(projectDropdown.waitForExistence(timeout: 3))
        projectDropdown.tap()

        let firstProject = app.buttons["review.projectOption.project-1"]
        XCTAssertTrue(firstProject.waitForExistence(timeout: 3))
        firstProject.tap()

        let saveEnabledPredicate = NSPredicate(format: "isEnabled == true")
        expectation(for: saveEnabledPredicate, evaluatedWith: saveButton, handler: nil)
        waitForExpectations(timeout: 5)

        // Tap Save Scan
        saveButton.tap()

        // Verify navigates to Scan Details screen
        let doneButton = app.buttons["scanDetails.doneButton"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()
    }

    @MainActor
    func testCancelScanning_returnsToProjectsList() throws {
        let app = launchApp(arguments: ["-UITesting", "-UITestSignedIn"])

        XCTAssertTrue(app.scrollViews["projects.list"].waitForExistence(timeout: 5))

        let newScanButton = app.buttons["home.newScan"]
        XCTAssertTrue(newScanButton.waitForExistence(timeout: 5))
        newScanButton.tap()

        let cancelButton = app.buttons["scancheck.cancelButton"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5))
        cancelButton.tap()

        XCTAssertTrue(app.scrollViews["projects.list"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testProjectDetail_addScan_completesFlowWithPreselectedProject() throws {
        let app = launchApp(arguments: ["-UITesting", "-UITestSignedIn"])

        XCTAssertTrue(app.scrollViews["projects.list"].waitForExistence(timeout: 5))

        let projectCard = app.staticTexts["projects.card.title.project-1"]
        XCTAssertTrue(projectCard.waitForExistence(timeout: 5))
        projectCard.tap()

        let addScanButton = app.buttons["projects.detail.addScan"]
        XCTAssertTrue(addScanButton.waitForExistence(timeout: 5))
        addScanButton.tap()

        let startScanButton = app.buttons["scancheck.startScan"]
        XCTAssertTrue(startScanButton.waitForExistence(timeout: 5))
        let startEnabledPredicate = NSPredicate(format: "isEnabled == true")
        expectation(for: startEnabledPredicate, evaluatedWith: startScanButton, handler: nil)
        waitForExpectations(timeout: 5)
        startScanButton.tap()

        let finishButton = app.buttons["scanning.finishButton"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 5))
        let isEnabledPredicate = NSPredicate(format: "isEnabled == true")
        expectation(for: isEnabledPredicate, evaluatedWith: finishButton, handler: nil)
        waitForExpectations(timeout: 5)
        finishButton.tap()

        let saveButton = app.buttons["review.saveButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))

        let scanNameField = app.textFields["review.scanNameField"]
        XCTAssertTrue(scanNameField.waitForExistence(timeout: 3))
        scanNameField.tap()
        scanNameField.typeText("Project Scan")

        let saveEnabledPredicate = NSPredicate(format: "isEnabled == true")
        expectation(for: saveEnabledPredicate, evaluatedWith: saveButton, handler: nil)
        waitForExpectations(timeout: 5)
        saveButton.tap()

        let doneButton = app.buttons["scanDetails.doneButton"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()
    }

    @MainActor
    func testNewProjectDetail_addScanPresentsScanReadiness() throws {
        let app = launchApp(arguments: ["-UITesting", "-UITestSignedIn"])

        let createButton = app.buttons["projects.create"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        createButton.tap()

        let nameField = app.textFields["projects.newProject.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Scan Project")

        let saveButton = app.buttons["projects.newProject.save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        let saveEnabledPredicate = NSPredicate(format: "isEnabled == true")
        expectation(for: saveEnabledPredicate, evaluatedWith: saveButton, handler: nil)
        waitForExpectations(timeout: 5)
        saveButton.tap()
        let addScanButton = app.buttons["projects.detail.addScan"]
        XCTAssertTrue(addScanButton.waitForExistence(timeout: 5))
        addScanButton.tap()
        XCTAssertTrue(app.buttons["scancheck.startScan"].waitForExistence(timeout: 5))
        let cancelButton = app.buttons["scancheck.cancelButton"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5))
        cancelButton.tap()
        XCTAssertTrue(app.scrollViews["projects.list"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func launchApp(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }
}
