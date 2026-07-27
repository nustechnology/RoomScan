//
//  ScanReadinessService.swift
//  roomscan
//

import AVFoundation
import Foundation

protocol ScanReadinessService: Sendable {
    func isDeviceSupported() -> Bool
    func cameraAuthorizationStatus() -> AVAuthorizationStatus
    func requestCameraAccess() async -> Bool
    func availableStorageBytes() -> Int64?
    func isCameraAvailable() async -> Bool
}
