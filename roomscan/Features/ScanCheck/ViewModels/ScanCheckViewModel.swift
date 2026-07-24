//
//  ScanCheckViewModel.swift
//  roomscan
//

import Foundation
import Observation
import AVFoundation

@MainActor
@Observable
final class ScanCheckViewModel {
    private static let minimumStorageBytes: Int64 = 100 * 1_024 * 1_024

    private let readinessService: any ScanReadinessService

    private(set) var deviceSupportStatus: ReadinessStatus = .checking
    private(set) var cameraPermissionStatus: ReadinessStatus = .checking
    private(set) var storageStatus: ReadinessStatus = .checking
    private(set) var cameraAvailabilityStatus: ReadinessStatus = .checking

    init(readinessService: any ScanReadinessService) {
        self.readinessService = readinessService
    }

    var allChecksPassed: Bool {
        deviceSupportStatus == .passed
            && cameraPermissionStatus == .passed
            && storageStatus == .passed
            && cameraAvailabilityStatus == .passed
    }

    var cameraPermissionNeedsSettings: Bool {
        if case .failed = cameraPermissionStatus { return true }
        return false
    }

    func runAllChecks() async {
        checkDeviceSupport()
        await checkCameraPermission()
        checkStorage()
        await checkCameraAvailability()
    }

    func requestCameraPermission() async {
        let granted = await readinessService.requestCameraAccess()
        cameraPermissionStatus = granted
            ? .passed
            : .failed(
                message: String(localized: "scancheck.camera.denied.message"),
                actionLabel: String(localized: "scancheck.camera.denied.action")
            )
    }

    func handleCameraPermissionTap() async {
        guard case .failed = cameraPermissionStatus else { return }
        await requestCameraPermission()
    }

    func handleForegroundReturn() {
        Task { await runAllChecks() }
    }

    private func checkDeviceSupport() {
        deviceSupportStatus = readinessService.isDeviceSupported()
            ? .passed
            : .failed(
                message: String(localized: "scancheck.device.unsupported.message"),
                actionLabel: nil
            )
    }

    private func checkCameraPermission() async {
        let status = readinessService.cameraAuthorizationStatus()
        switch status {
        case .authorized:
            cameraPermissionStatus = .passed
        case .notDetermined:
            await requestCameraPermission()
        case .denied, .restricted:
            cameraPermissionStatus = .failed(
                message: String(localized: "scancheck.camera.denied.message"),
                actionLabel: String(localized: "scancheck.camera.denied.action")
            )
        @unknown default:
            cameraPermissionStatus = .failed(
                message: String(localized: "scancheck.camera.denied.message"),
                actionLabel: String(localized: "scancheck.camera.denied.action")
            )
        }
    }

    private func checkStorage() {
        guard let freeSpace = readinessService.availableStorageBytes() else {
            storageStatus = .failed(
                message: String(localized: "scancheck.storage.insufficient.message"),
                actionLabel: nil
            )
            return
        }

        storageStatus = freeSpace >= Self.minimumStorageBytes
            ? .passed
            : .failed(
                message: String(localized: "scancheck.storage.insufficient.message"),
                actionLabel: nil
            )
    }

    private func checkCameraAvailability() async {
        let available = await readinessService.isCameraAvailable()
        cameraAvailabilityStatus = available
            ? .passed
            : .failed(
                message: String(localized: "scancheck.camera.unavailable"),
                actionLabel: nil
            )
    }
}
