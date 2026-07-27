//
//  ScanReadinessServiceFactory.swift
//  roomscan
//

import Foundation
import AVFoundation

enum ScanReadinessServiceFactory {
    static func makeService() -> any ScanReadinessService {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-UITesting")
        if isUITesting {
            return MockUITestScanReadinessService()
        }
        return RealScanReadinessService()
    }
}

struct MockUITestScanReadinessService: ScanReadinessService {
    func isDeviceSupported() -> Bool { true }
    func cameraAuthorizationStatus() -> AVAuthorizationStatus { .authorized }
    func requestCameraAccess() async -> Bool { true }
    func availableStorageBytes() -> Int64? { 500 * 1024 * 1024 }
    func isCameraAvailable() async -> Bool { true }
}
