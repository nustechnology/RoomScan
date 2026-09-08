//
//  ScanTelemetry.swift
//  roomscan
//

import Foundation
import os

final class ScanTelemetry: @unchecked Sendable {
    static let shared = ScanTelemetry()

    private let logger = Logger(subsystem: "com.roomscan.app", category: "Telemetry")
    private let signposter = OSSignposter(subsystem: "com.roomscan.app", category: "CameraStartup")

    private var startScanTimestamp: CFAbsoluteTime?
    private var signpostState: OSSignpostIntervalState?

    private init() {}

    func recordStartScanTapped() {
        let now = CFAbsoluteTimeGetCurrent()
        startScanTimestamp = now
        logger.info("[Telemetry] 🚀 Start Scan Tapped at \(now)")
    }

    func recordPreScanTransitionBegan() {
        logMilestone("Pre-scan transition began")
    }

    func recordCameraViewInitialized() {
        logMilestone("CameraScanView initialized")
    }

    func recordRoomCaptureViewCreated() {
        logMilestone("RoomCaptureView created")
    }

    func recordSessionAttached() {
        logMilestone("RoomCaptureSession attached")
    }

    func recordSessionRunCalled() {
        logMilestone("RoomCaptureSession.run() called")
    }

    func recordFirstFrameReceived() {
        if let start = startScanTimestamp {
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
            logger.info("[Telemetry] 🟢 First camera frame / RoomPlan update received in \(elapsedMs, format: .fixed(precision: 1)) ms")
        } else {
            logger.info("[Telemetry] 🟢 First camera frame / RoomPlan update received")
        }
    }

    func recordUnexpectedSessionEnd() {
        logger.error("[Telemetry] ⚠️ RoomCaptureSession ended unexpectedly (tracking lost)")
    }

    func recordDraftManifestSaveFailed(_ error: Error) {
        logger.error("[Telemetry] ⚠️ Failed to save draft manifest: \(error.localizedDescription)")
    }

    private func logMilestone(_ name: String) {
        if let start = startScanTimestamp {
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
            logger.info("[Telemetry] ⏱️ \(name) [+\(elapsedMs, format: .fixed(precision: 1)) ms]")
        } else {
            logger.info("[Telemetry] ⏱️ \(name)")
        }
    }
}
