//
//  RealScanReadinessService.swift
//  roomscan
//

import Foundation
import ARKit
import AVFoundation

struct RealScanReadinessService: ScanReadinessService {
    func isDeviceSupported() -> Bool {
        // RoomPlan requires a LiDAR-capable device.
        // This check must match the capability gate used by the capture feature.
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    func cameraAuthorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    func requestCameraAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func availableStorageBytes() -> Int64? {
        try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }

    func isCameraAvailable() async -> Bool {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: .back
        )

        guard let camera = discoverySession.devices.first else {
            return false
        }

        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        guard authStatus == .authorized else {
            return true
        }

        do {
            try camera.lockForConfiguration()
            camera.unlockForConfiguration()
            return true
        } catch {
            return false
        }
    }
}
