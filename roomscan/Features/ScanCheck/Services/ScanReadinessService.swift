//
//  ScanReadinessService.swift
//  roomscan
//

import Foundation
import AVFoundation

protocol ScanReadinessService: Sendable {
    func isDeviceSupported() -> Bool
    func cameraAuthorizationStatus() -> AVAuthorizationStatus
    func requestCameraAccess() async -> Bool
    func availableStorageBytes() -> Int64?
    func isCameraAvailable() async -> Bool
}
