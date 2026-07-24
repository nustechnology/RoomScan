//
//  ScanCheckViewModelTests.swift
//  roomscanTests
//

import Foundation
import AVFoundation
import Testing
@testable import roomscan

@MainActor
struct ScanCheckViewModelTests {
    // MARK: - Initial State

    @Test func initialStateHasAllChecksAsChecking() {
        let mock = MockScanReadinessService()
        let viewModel = ScanCheckViewModel(readinessService: mock)

        #expect(viewModel.deviceSupportStatus == .checking)
        #expect(viewModel.cameraPermissionStatus == .checking)
        #expect(viewModel.storageStatus == .checking)
        #expect(viewModel.cameraAvailabilityStatus == .checking)
    }

    @Test func allChecksPassedIsFalseInitially() {
        let mock = MockScanReadinessService()
        let viewModel = ScanCheckViewModel(readinessService: mock)

        #expect(viewModel.allChecksPassed == false)
    }

    @Test func cameraPermissionNeedsSettingsIsFalseInitially() {
        let mock = MockScanReadinessService()
        let viewModel = ScanCheckViewModel(readinessService: mock)

        #expect(viewModel.cameraPermissionNeedsSettings == false)
    }

    // MARK: - All Checks Pass

    @Test func allChecksPassedIsTrueWhenAllPass() async {
        let mock = MockScanReadinessService()
        let viewModel = ScanCheckViewModel(readinessService: mock)

        await viewModel.runAllChecks()

        #expect(viewModel.allChecksPassed == true)
    }

    // MARK: - Device Support

    @Test func deviceSupportPassedWhenSupported() async {
        var mock = MockScanReadinessService()
        mock.isDeviceSupportedResult = true
        let viewModel = ScanCheckViewModel(readinessService: mock)

        await viewModel.runAllChecks()

        #expect(viewModel.deviceSupportStatus == .passed)
    }

    @Test func deviceSupportFailedWhenNotSupported() async {
        var mock = MockScanReadinessService()
        mock.isDeviceSupportedResult = false
        let viewModel = ScanCheckViewModel(readinessService: mock)

        await viewModel.runAllChecks()

        #expect(viewModel.deviceSupportStatus != .passed)
    }

    @Test func deviceSupportFailureContainsMessage() async {
        var mock = MockScanReadinessService()
        mock.isDeviceSupportedResult = false
        let viewModel = ScanCheckViewModel(readinessService: mock)

        await viewModel.runAllChecks()

        if case .failed(let message, _) = viewModel.deviceSupportStatus {
            #expect(!message.isEmpty)
        } else {
            #expect(false, "Expected failed status")
        }
    }

    // MARK: - Camera Permission

    @Test func cameraPermissionPassedWhenAuthorized() async {
        var mock = MockScanReadinessService()
        mock.cameraAuthorizationStatusResult = .authorized
        let viewModel = ScanCheckViewModel(readinessService: mock)

        await viewModel.runAllChecks()

        #expect(viewModel.cameraPermissionStatus == .passed)
    }

    @Test func cameraPermissionRequestsAccessWhenNotDetermined() async {
        var mock = MockScanReadinessService()
        mock.cameraAuthorizationStatusResult = .notDetermined
        mock.requestCameraAccessResult = true
        let viewModel = ScanCheckViewModel(readinessService: mock)

        await viewModel.runAllChecks()

        #expect(viewModel.cameraPermissionStatus == .passed)
    }

    @Test func cameraPermissionRequestsAccessWhenNotDeterminedAndDenied() async {
        var mock = MockScanReadinessService()
        mock.cameraAuthorizationStatusResult = .notDetermined
        mock.requestCameraAccessResult = false
        let viewModel = ScanCheckViewModel(readinessService: mock)

        await viewModel.runAllChecks()

        #expect(viewModel.cameraPermissionStatus != .passed)
    }

    @Test func cameraPermissionFailedWhenDenied() async {
        var mock = MockScanReadinessService()
        mock.cameraAuthorizationStatusResult = .denied
        let viewModel = ScanCheckViewModel(readinessService: mock)

        await viewModel.runAllChecks()

        #expect(viewModel.cameraPermissionStatus != .passed)
    }

    @Test func cameraPermissionFailedWhenRestricted() async {
        var mock = MockScanReadinessService()
        mock.cameraAuthorizationStatusResult = .restricted
        let viewModel = ScanCheckViewModel(readinessService: mock)

        await viewModel.runAllChecks()

        #expect(viewModel.cameraPermissionStatus != .passed)
    }

    @Test func cameraPermissionFailureContainsActionLabel() async {
        var mock = MockScanReadinessService()
        mock.cameraAuthorizationStatusResult = .denied
        let viewModel = ScanCheckViewModel(readinessService: mock)

        await viewModel.runAllChecks()

        if case .failed(_, let actionLabel) = viewModel.cameraPermissionStatus, let actionLabel {
            #expect(!actionLabel.isEmpty)
        } else {
            #expect(false, "Expected failed status with action label")
        }
    }

    @Test func cameraPermissionNeedsSettingsTrueWhenDenied() async {
        var mock = MockScanReadinessService()
        mock.cameraAuthorizationStatusResult = .denied
        let viewModel = ScanCheckViewModel(readinessService: mock)

        await viewModel.runAllChecks()

        #expect(viewModel.cameraPermissionNeedsSettings == true)
    }

    @Test func cameraPermissionNeedsSettingsFalseWhenNotFailed() async {
        var mock = MockScanReadinessService()
        mock.cameraAuthorizationStatusResult = .authorized
        let viewModel = ScanCheckViewModel(readinessService: mock)

        await viewModel.runAllChecks()

        #expect(viewModel.cameraPermissionNeedsSettings == false)
    }

    // MARK: - Storage

    @Test func storagePassedWhenSufficientSpace() async {
        var mock = MockScanReadinessService()
        mock.availableStorageBytesResult = 200 * 1_024 * 1_024
        let viewModel = ScanCheckViewModel(readinessService: mock)

        await viewModel.runAllChecks()

        #expect(viewModel.storageStatus == .passed)
    }

    @Test func storageFailedWhenInsufficientSpace() async {
        var mock = MockScanReadinessService()
        mock.availableStorageBytesResult = 50 * 1_024 * 1_024
        let viewModel = ScanCheckViewModel(readinessService: mock)

        await viewModel.runAllChecks()

        #expect(viewModel.storageStatus != .passed)
    }

    @Test func storageFailedWhenCannotDetermineSpace() async {
        var mock = MockScanReadinessService()
        mock.availableStorageBytesResult = nil
        let viewModel = ScanCheckViewModel(readinessService: mock)

        await viewModel.runAllChecks()

        #expect(viewModel.storageStatus != .passed)
    }

    @Test func storageFailureContainsMessage() async {
        var mock = MockScanReadinessService()
        mock.availableStorageBytesResult = 50 * 1_024 * 1_024
        let viewModel = ScanCheckViewModel(readinessService: mock)

        await viewModel.runAllChecks()

        if case .failed(let message, _) = viewModel.storageStatus {
            #expect(!message.isEmpty)
        } else {
            #expect(false, "Expected failed status")
        }
    }

    // MARK: - Camera Availability

    @Test func cameraAvailabilityPassedWhenAvailable() async {
        var mock = MockScanReadinessService()
        mock.isCameraAvailableResult = true
        let viewModel = ScanCheckViewModel(readinessService: mock)

        await viewModel.runAllChecks()

        #expect(viewModel.cameraAvailabilityStatus == .passed)
    }

    @Test func cameraAvailabilityFailedWhenUnavailable() async {
        var mock = MockScanReadinessService()
        mock.isCameraAvailableResult = false
        let viewModel = ScanCheckViewModel(readinessService: mock)

        await viewModel.runAllChecks()

        #expect(viewModel.cameraAvailabilityStatus != .passed)
    }

    // MARK: - allChecksPassed With Mixed Results

    @Test func allChecksPassedFalseWhenDeviceNotSupported() async {
        var mock = MockScanReadinessService()
        mock.isDeviceSupportedResult = false
        let viewModel = ScanCheckViewModel(readinessService: mock)

        await viewModel.runAllChecks()

        #expect(viewModel.allChecksPassed == false)
    }

    @Test func allChecksPassedFalseWhenCameraDenied() async {
        var mock = MockScanReadinessService()
        mock.cameraAuthorizationStatusResult = .denied
        let viewModel = ScanCheckViewModel(readinessService: mock)

        await viewModel.runAllChecks()

        #expect(viewModel.allChecksPassed == false)
    }

    @Test func allChecksPassedFalseWhenStorageInsufficient() async {
        var mock = MockScanReadinessService()
        mock.availableStorageBytesResult = 50 * 1_024 * 1_024
        let viewModel = ScanCheckViewModel(readinessService: mock)

        await viewModel.runAllChecks()

        #expect(viewModel.allChecksPassed == false)
    }

    @Test func allChecksPassedFalseWhenCameraUnavailable() async {
        var mock = MockScanReadinessService()
        mock.isCameraAvailableResult = false
        let viewModel = ScanCheckViewModel(readinessService: mock)

        await viewModel.runAllChecks()

        #expect(viewModel.allChecksPassed == false)
    }

    // MARK: - handleForegroundReturn

    @Test func handleForegroundReturnDoesNotCrash() {
        let mock = MockScanReadinessService()
        let viewModel = ScanCheckViewModel(readinessService: mock)

        viewModel.handleForegroundReturn()
    }
}
