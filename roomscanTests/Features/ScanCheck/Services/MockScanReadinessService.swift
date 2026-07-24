//
//  MockScanReadinessService.swift
//  roomscanTests
//

import Foundation
import AVFoundation
@testable import roomscan

struct MockScanReadinessService: ScanReadinessService {
    var isDeviceSupportedResult: Bool = true
    var cameraAuthorizationStatusResult: AVAuthorizationStatus = .authorized
    var requestCameraAccessResult: Bool = true
    var availableStorageBytesResult: Int64? = 500 * 1_024 * 1_024
    var isCameraAvailableResult: Bool = true

    func isDeviceSupported() -> Bool {
        isDeviceSupportedResult
    }

    func cameraAuthorizationStatus() -> AVAuthorizationStatus {
        cameraAuthorizationStatusResult
    }

    func requestCameraAccess() async -> Bool {
        requestCameraAccessResult
    }

    func availableStorageBytes() -> Int64? {
        availableStorageBytesResult
    }

    func isCameraAvailable() async -> Bool {
        isCameraAvailableResult
    }
}
