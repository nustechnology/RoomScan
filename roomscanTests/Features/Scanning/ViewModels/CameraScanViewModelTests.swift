//
//  CameraScanViewModelTests.swift
//  roomscanTests
//

import XCTest
@testable import roomscan

@MainActor
final class CameraScanViewModelTests: XCTestCase {
    private var mockCaptureService: MockRoomCaptureService!
    private var viewModel: CameraScanViewModel!

    override func setUp() async throws {
        try await super.setUp()
        mockCaptureService = MockRoomCaptureService(simulateStructureDelay: 0)
        viewModel = CameraScanViewModel(captureService: mockCaptureService)
    }

    override func tearDown() async throws {
        viewModel = nil
        mockCaptureService = nil
        try await super.tearDown()
    }

    func testStartScanning_disablesAutoLockAndStartsSession() {
        viewModel.startScanning()

        XCTAssertTrue(viewModel.isScanning)
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
    }

    func testStopScanning_restoresAutoLockAndStopsSession() {
        viewModel.startScanning()
        viewModel.stopScanning()

        XCTAssertFalse(viewModel.isScanning)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
    }

    func testStopScanning_restoresPreviousAutoLockSetting() {
        UIApplication.shared.isIdleTimerDisabled = true

        viewModel.startScanning()
        viewModel.stopScanning()

        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func testMinimalStructure_enablesFinishButton() async {
        viewModel.startScanning()
        // Wait for mock service to publish minimal structure
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(viewModel.hasMinimalStructure)
    }

    func testCancelTapped_showsConfirmationModal() {
        viewModel.startScanning()
        viewModel.handleCancelTapped()

        XCTAssertTrue(viewModel.showCancelConfirmation)
        XCTAssertFalse(mockCaptureService.isScanning)

        viewModel.resumeScanning()

        XCTAssertFalse(viewModel.showCancelConfirmation)
        XCTAssertTrue(mockCaptureService.isScanning)
    }

    func testDiscardAndExit_stopsScanningAndClosesModal() {
        viewModel.startScanning()
        viewModel.handleCancelTapped()
        viewModel.discardAndExit()

        XCTAssertFalse(viewModel.showCancelConfirmation)
        XCTAssertFalse(viewModel.isScanning)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
    }

    func testFinishScan_returnsDraftAndStopsSession() async {
        viewModel.startScanning()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let draft = await viewModel.finishScan()

        XCTAssertNotNil(draft)
        XCTAssertFalse(viewModel.isScanning)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
    }

    func testFinishScan_persistsSourceProjectForRecovery() async {
        let storageService = LocalScanStorageService()
        storageService.clearDraftManifest()
        let contextualViewModel = CameraScanViewModel(
            sourceProjectID: "project-2",
            captureService: mockCaptureService,
            storageService: storageService
        )
        contextualViewModel.startScanning()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let draft = await contextualViewModel.finishScan()
        let recoveredDraft = storageService.loadDraftManifest()

        XCTAssertEqual(draft?.projectID, "project-2")
        XCTAssertEqual(recoveredDraft?.projectID, "project-2")
        storageService.clearDraftManifest()
    }

    func testStorageFull_setsErrorState() async {
        viewModel.startScanning()
        mockCaptureService.setStorageFullForTesting(true)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(viewModel.isStorageFull)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testResumeScanning_restartsStructureTimerWhenMinimalStructureNotYetDetected() async {
        let delayedService = MockRoomCaptureService(simulateStructureDelay: 0.1)
        let delayedViewModel = CameraScanViewModel(captureService: delayedService)

        delayedViewModel.startScanning()
        XCTAssertFalse(delayedViewModel.hasMinimalStructure)

        delayedViewModel.handleCancelTapped()
        XCTAssertFalse(delayedService.isScanning)
        XCTAssertFalse(delayedViewModel.hasMinimalStructure)

        delayedViewModel.resumeScanning()
        XCTAssertTrue(delayedService.isScanning)

        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(delayedViewModel.hasMinimalStructure)
    }
}
