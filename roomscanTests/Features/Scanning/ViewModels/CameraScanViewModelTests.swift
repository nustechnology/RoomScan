//
//  CameraScanViewModelTests.swift
//  roomscanTests
//

@testable import roomscan
import UIKit
import XCTest

@MainActor
final class CameraScanViewModelTests: XCTestCase {
    private var mockCaptureService: MockRoomCaptureService!
    private var viewModel: CameraScanViewModel!

    override func setUp() async throws {
        try await super.setUp()
        mockCaptureService = MockRoomCaptureService(simulateStructureDelay: 0)
        viewModel = makeViewModel()
    }

    override func tearDown() async throws {
        // deinit restores the idle timer in an unawaited Task, so stop explicitly
        // to keep UIApplication.shared.isIdleTimerDisabled deterministic between tests.
        viewModel?.stopScanning()
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
        await waitUntil { viewModel.hasMinimalStructure }
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
        await waitUntil { viewModel.hasMinimalStructure }

        let draft = await viewModel.finishScan()

        XCTAssertNotNil(draft)
        XCTAssertFalse(viewModel.isScanning)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
        XCTAssertEqual(mockCaptureService.stopCallCount, 1)
    }

    func testPauseThenResume_doesNotFinishScan() async {
        viewModel.startScanning()
        await waitUntil { viewModel.hasMinimalStructure }

        viewModel.togglePause()
        XCTAssertTrue(viewModel.isPaused)
        XCTAssertNil(viewModel.capturedDraft)

        viewModel.togglePause()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(viewModel.isPaused)
        XCTAssertTrue(viewModel.isScanning)
        XCTAssertNil(viewModel.capturedDraft)
        XCTAssertFalse(viewModel.isProcessingFinish)
        XCTAssertTrue(mockCaptureService.isScanning)
    }

    func testUnexpectedSessionEnd_whilePaused_doesNotFinishScan() async {
        viewModel.startScanning()
        await waitUntil { viewModel.hasMinimalStructure }

        viewModel.togglePause()
        mockCaptureService.simulateUnexpectedSessionEnd()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(viewModel.isPaused)
        XCTAssertTrue(viewModel.isScanning)
        XCTAssertNil(viewModel.capturedDraft)
        XCTAssertFalse(viewModel.isProcessingFinish)

        viewModel.togglePause()
        XCTAssertFalse(viewModel.isPaused)
        XCTAssertTrue(mockCaptureService.isScanning)
        XCTAssertNil(viewModel.capturedDraft)
    }

    func testUnexpectedSessionEnd_afterResumeBeforeFirstUpdate_finishesScan() async {
        viewModel.startScanning()
        await waitUntil { viewModel.hasMinimalStructure }

        viewModel.togglePause()
        viewModel.togglePause()
        XCTAssertFalse(viewModel.isPaused)
        XCTAssertNil(viewModel.capturedDraft)

        mockCaptureService.simulateUnexpectedSessionEnd()
        await waitUntil { viewModel.capturedDraft != nil }

        XCTAssertNotNil(viewModel.capturedDraft)
        XCTAssertFalse(viewModel.isScanning)
        XCTAssertFalse(viewModel.isPaused)
        XCTAssertFalse(viewModel.showTrackingLostAlert)
    }

    func testUnexpectedSessionEnd_withStructure_finishesScanAutomatically() async {
        viewModel.startScanning()
        await waitUntil { viewModel.hasMinimalStructure }

        mockCaptureService.simulateUnexpectedSessionEnd()
        await waitUntil { viewModel.capturedDraft != nil }

        XCTAssertNotNil(viewModel.capturedDraft)
        XCTAssertFalse(viewModel.isScanning)
        XCTAssertFalse(viewModel.isPaused)
        XCTAssertFalse(viewModel.showTrackingLostAlert)
        XCTAssertEqual(mockCaptureService.stopCallCount, 0)

        viewModel.togglePause()
        viewModel.resumeScanning()
        XCTAssertFalse(mockCaptureService.isScanning)
        XCTAssertFalse(viewModel.isScanning)
    }

    func testStopThenStart_staleSessionEndDoesNotFinishScan() async {
        viewModel.startScanning()
        await waitUntil { viewModel.hasMinimalStructure }

        mockCaptureService.deferNextStopTerminalCallback()
        viewModel.stopScanning()
        viewModel.startScanning()
        mockCaptureService.simulateStaleSessionEnd()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(viewModel.capturedDraft)
        XCTAssertTrue(viewModel.isScanning)
        XCTAssertFalse(viewModel.isProcessingFinish)
        XCTAssertFalse(viewModel.showTrackingLostAlert)
    }

    func testUnexpectedSessionEnd_withoutStructure_showsTrackingLostAlert() async {
        let delayedService = MockRoomCaptureService(simulateStructureDelay: 10)
        let delayedViewModel = makeViewModel(captureService: delayedService)

        delayedViewModel.startScanning()
        XCTAssertFalse(delayedViewModel.hasMinimalStructure)

        delayedService.simulateUnexpectedSessionEnd()
        await waitUntil { delayedViewModel.showTrackingLostAlert }

        XCTAssertTrue(delayedViewModel.showTrackingLostAlert)
        XCTAssertFalse(delayedViewModel.isScanning)
        XCTAssertNil(delayedViewModel.capturedDraft)
        XCTAssertEqual(delayedService.stopCallCount, 0)

        delayedViewModel.togglePause()
        XCTAssertFalse(delayedService.isScanning)

        delayedViewModel.retryAfterTrackingLost()
        XCTAssertTrue(delayedViewModel.isScanning)
        XCTAssertTrue(delayedService.isScanning)
        XCTAssertFalse(delayedViewModel.showTrackingLostAlert)

        delayedViewModel.stopScanning()
    }

    func testFinishScan_persistsSourceProjectForRecovery() async {
        let storageService = LocalScanStorageService()
        storageService.clearDraftManifest()
        let contextualViewModel = makeViewModel(
            sourceProjectID: "project-2",
            storageService: storageService
        )
        contextualViewModel.startScanning()
        await waitUntil { contextualViewModel.hasMinimalStructure }

        let draft = await contextualViewModel.finishScan()
        let recoveredDraft = storageService.loadDraftManifest()

        XCTAssertEqual(draft?.projectID, "project-2")
        XCTAssertEqual(recoveredDraft?.projectID, "project-2")
        storageService.clearDraftManifest()
    }

    func testStorageFull_setsErrorState() async {
        viewModel.startScanning()
        mockCaptureService.setStorageFullForTesting(true)
        await waitUntil { viewModel.isStorageFull }

        XCTAssertTrue(viewModel.isStorageFull)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testResumeScanning_restartsStructureTimerWhenMinimalStructureNotYetDetected() async {
        let delayedService = MockRoomCaptureService(simulateStructureDelay: 0.1)
        let delayedViewModel = makeViewModel(captureService: delayedService)

        delayedViewModel.startScanning()
        XCTAssertFalse(delayedViewModel.hasMinimalStructure)

        delayedViewModel.handleCancelTapped()
        XCTAssertFalse(delayedService.isScanning)
        XCTAssertFalse(delayedViewModel.hasMinimalStructure)

        delayedViewModel.resumeScanning()
        XCTAssertTrue(delayedService.isScanning)

        await waitUntil { delayedViewModel.hasMinimalStructure }

        delayedViewModel.stopScanning()
    }

    private func makeViewModel(
        sourceProjectID: String? = nil,
        captureService: RoomCaptureService? = nil,
        storageService: ScanStorageService = LocalScanStorageService()
    ) -> CameraScanViewModel {
        CameraScanViewModel(
            sourceProjectID: sourceProjectID,
            captureService: captureService ?? mockCaptureService,
            storageService: storageService
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("Timed out waiting for condition", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
