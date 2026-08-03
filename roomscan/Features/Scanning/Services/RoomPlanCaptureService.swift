//
//  RoomPlanCaptureService.swift
//  roomscan
//

import ARKit
import Combine
import Foundation
import Metal
import SceneKit
import SwiftUI
#if canImport(RoomPlan)
import RoomPlan
#endif

@MainActor
enum RoomCaptureServiceFactory {
    static func makeService(storageService: ScanStorageService? = nil) -> RoomCaptureService {
        let storage = storageService ?? LocalScanStorageService()
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-UITesting")
        #if canImport(RoomPlan)
        if #available(iOS 16.0, *), RoomCaptureSession.isSupported, !isUITesting {
            return RoomPlanCaptureService(storageService: storage)
        }
        #endif
        return MockRoomCaptureService(storageService: storage)
    }
}

#if canImport(RoomPlan)
@available(iOS 16.0, *)
@MainActor
final class RoomPlanCaptureService: NSObject, RoomCaptureService, RoomCaptureSessionDelegate, @unchecked Sendable {
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var hasMinimalStructure: Bool = false
    @Published private(set) var isStorageFull: Bool = false
    @Published private(set) var currentInstruction: String?

    private(set) var roomCaptureSession: RoomCaptureSession?
    private var currentCapturedRoom: CapturedRoom?
    private var finalCapturedRoomData: CapturedRoomData?
    private var captureEndError: Error?
    private let storageService: ScanStorageService
    private var isCaptureSessionRunning = false
    private var isPaused = false
    private var pausedARConfiguration: ARConfiguration?

    var minimalStructurePublisher: AnyPublisher<Bool, Never> {
        $hasMinimalStructure.eraseToAnyPublisher()
    }

    var storageFullPublisher: AnyPublisher<Bool, Never> {
        $isStorageFull.eraseToAnyPublisher()
    }

    var instructionPublisher: AnyPublisher<String?, Never> {
        $currentInstruction.eraseToAnyPublisher()
    }

    init(storageService: ScanStorageService? = nil) {
        self.storageService = storageService ?? LocalScanStorageService()
        super.init()
    }

    private var isSessionPendingStart = false

    func attachCaptureSession(_ session: RoomCaptureSession) {
        if let previousSession = roomCaptureSession, previousSession !== session,
           isCaptureSessionRunning {
            print("[RoomScan Log] Stopping replaced RoomCaptureSession.")
            previousSession.stop()
            isCaptureSessionRunning = false
        }

        session.delegate = self
        self.roomCaptureSession = session
        ScanTelemetry.shared.recordSessionAttached()
        if isSessionPendingStart || isScanning {
            let config = RoomCaptureSession.Configuration()
            session.run(configuration: config)
            ScanTelemetry.shared.recordSessionRunCalled()
            isSessionPendingStart = false
            isCaptureSessionRunning = true
            print("[RoomScan Log] Attached RoomCaptureSession.run() called successfully.")
        }
    }

    func startSession() {
        print("[RoomScan Log] Starting RoomCaptureSession...")
        isScanning = true
        hasMinimalStructure = false
        isStorageFull = false
        isSessionPendingStart = true
        isPaused = false
        pausedARConfiguration = nil
        hasRecordedFirstFrame = false
        finalCapturedRoomData = nil
        captureEndError = nil

        if let session = roomCaptureSession {
            let config = RoomCaptureSession.Configuration()
            session.run(configuration: config)
            ScanTelemetry.shared.recordSessionRunCalled()
            isSessionPendingStart = false
            isCaptureSessionRunning = true
            print("[RoomScan Log] RoomCaptureSession.run() called successfully.")
        }
    }

    func pauseSession() {
        guard isCaptureSessionRunning, !isPaused, let arSession = roomCaptureSession?.arSession else { return }
        pausedARConfiguration = arSession.configuration
        arSession.pause()
        isPaused = true
        isScanning = false
        print("[RoomScan Log] ARSession paused while scanning is suspended.")
    }

    func resumeSession() {
        guard isCaptureSessionRunning, isPaused, let arSession = roomCaptureSession?.arSession else { return }
        // Resuming must restart the ARSession that `pauseSession` paused. Re-running the
        // RoomCaptureSession leaves the AR session paused and also discards the in-progress scan.
        guard let configuration = pausedARConfiguration ?? arSession.configuration else {
            print("[RoomScan Log-ERROR] Cannot resume: ARSession has no configuration.")
            return
        }
        arSession.run(configuration)
        pausedARConfiguration = nil
        isPaused = false
        isScanning = true
        print("[RoomScan Log] ARSession resumed.")
    }

    func stopSession() {
        guard isCaptureSessionRunning || isSessionPendingStart else { return }
        print("[RoomScan Log] Stopping RoomCaptureSession...")
        isScanning = false
        if isCaptureSessionRunning {
            roomCaptureSession?.stop()
        }
        isCaptureSessionRunning = false
        isSessionPendingStart = false
        isPaused = false
        pausedARConfiguration = nil
    }

    func finishScan() async throws -> RoomScanDraft {
        print("[RoomScan STEP 3.1] Stopping session in RoomPlanCaptureService...")
        stopSession()

        print("[RoomScan STEP 3.2] Awaiting final RoomPlan capture data...")
        for _ in 0..<20 where finalCapturedRoomData == nil && captureEndError == nil {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        if let captureEndError {
            throw captureEndError
        }

        let capturedRoom = try await roomForExport()

        let draftID = UUID().uuidString
        let draftDirectory = try LocalScanStorageService.makeCaptureDraftDirectory(id: draftID)
        let meshURL = draftDirectory.appendingPathComponent("mesh.usdz")
        let thumbnailURL = draftDirectory.appendingPathComponent("thumbnail.jpg")

        print("[RoomScan STEP 3.3] Exporting CapturedRoom USDZ mesh...")
        logCapturedRoom(capturedRoom)
        let roomToExport = capturedRoom
        let exportURL = meshURL
        try await Task.detached(priority: .userInitiated) {
            try roomToExport.export(to: exportURL)
        }.value

        let meshSize = (try? FileManager.default.attributesOfItem(atPath: meshURL.path)[.size] as? Int64) ?? 0
        guard meshSize > 0 else {
            throw RoomPlanCaptureError.invalidExport
        }
        print("[RoomScan STEP 3.4] Room mesh exported successfully to: \(meshURL.path) (\(meshSize) bytes)")

        do {
            try await Task.detached(priority: .utility) {
                try Self.generateThumbnail(from: meshURL, destination: thumbnailURL)
            }.value
        } catch {
            print("[RoomScan STEP 3.5-WARNING] Thumbnail generation failed: \(error.localizedDescription)")
            try generateFallbackThumbnail(destination: thumbnailURL)
        }

        let draft = RoomScanDraft(id: draftID, meshFileURL: meshURL, thumbnailFileURL: thumbnailURL)
        do {
            try storageService.saveDraftManifest(draft)
        } catch {
            print("[RoomScan STEP 3.6-WARNING] Failed to save draft manifest: \(error.localizedDescription)")
            ScanTelemetry.shared.recordDraftManifestSaveFailed(error)
        }
        return draft
    }

    private var hasRecordedFirstFrame = false

    // MARK: - RoomCaptureSessionDelegate
    nonisolated func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        Task { @MainActor in
            if !self.hasRecordedFirstFrame {
                self.hasRecordedFirstFrame = true
                ScanTelemetry.shared.recordFirstFrameReceived()
            }
            self.currentCapturedRoom = room
            let hasStructure = !room.walls.isEmpty || !room.floors.isEmpty
            if hasStructure && !self.hasMinimalStructure {
                self.hasMinimalStructure = true
            }
            self.checkMidScanStorageCapacity()
        }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.currentInstruction = Self.localizedInstruction(for: instruction)
        }
    }

    nonisolated private static func localizedInstruction(
        for instruction: RoomCaptureSession.Instruction
    ) -> String? {
        switch instruction {
        case .moveCloseToWall:
            String(localized: "scanning.instruction.move_closer_to_wall")
        case .moveAwayFromWall:
            String(localized: "scanning.instruction.move_away_from_wall")
        case .slowDown:
            String(localized: "scanning.instruction.slow_down")
        case .turnOnLight:
            String(localized: "scanning.instruction.turn_on_light")
        case .lowTexture:
            String(localized: "scanning.instruction.low_texture")
        case .normal:
            nil
        default:
            nil
        }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: (any Error)?) {
        Task { @MainActor in
            self.isScanning = false
            self.finalCapturedRoomData = data
            self.captureEndError = error
        }
    }

    private func checkMidScanStorageCapacity() {
        do {
            let values = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            ).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])

            if let availableBytes = values.volumeAvailableCapacityForImportantUsage, availableBytes < 50_000_000 {
                self.isStorageFull = true
                self.stopSession()
            }
        } catch {
            // Ignore error
        }
    }

    private func logCapturedRoom(_ room: CapturedRoom) {
        print("-------------------- [CAPTURED ROOM DATA] --------------------")
        print("  - Walls count: \(room.walls.count)")
        print("  - Floors count: \(room.floors.count)")
        print("  - Doors count: \(room.doors.count)")
        print("  - Windows count: \(room.windows.count)")
        print("  - Openings count: \(room.openings.count)")
        print("  - Objects count: \(room.objects.count)")
        print("--------------------------------------------------------------")
    }

    private func roomForExport() async throws -> CapturedRoom {
        if let currentCapturedRoom, hasRenderableContent(currentCapturedRoom) {
            print("[RoomScan STEP 3.2] Using realtime CapturedRoom with detected structure.")
            return currentCapturedRoom
        }

        if let finalCapturedRoomData {
            let processedRoom = try await RoomBuilder(options: [.beautifyObjects])
                .capturedRoom(from: finalCapturedRoomData)
            if hasRenderableContent(processedRoom) {
                print("[RoomScan STEP 3.2] Using processed final CapturedRoomData.")
                return processedRoom
            }
            print("[RoomScan STEP 3.2-ERROR] Processed final room contains no renderable structure.")
        }

        throw RoomPlanCaptureError.missingCapturedRoom
    }

    private func hasRenderableContent(_ room: CapturedRoom) -> Bool {
        !room.walls.isEmpty ||
            !room.floors.isEmpty ||
            !room.doors.isEmpty ||
            !room.windows.isEmpty ||
            !room.openings.isEmpty ||
            !room.objects.isEmpty
    }

    private func generateFallbackThumbnail(destination: URL) throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 480))
        let data = renderer.jpegData(withCompressionQuality: 0.82) { context in
            UIColor(
                red: 239 / 255,
                green: 244 / 255,
                blue: 250 / 255,
                alpha: 1
            ).setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        }
        try data.write(to: destination, options: .atomic)
    }

    nonisolated private static func generateThumbnail(from meshURL: URL, destination: URL) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw CocoaError(.featureUnsupported)
        }
        let scene = try SCNScene(url: meshURL, options: nil)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.autoenablesDefaultLighting = true

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 4, y: 3, z: 5)
        cameraNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cameraNode)
        renderer.pointOfView = cameraNode

        let image = renderer.snapshot(
            atTime: 0,
            with: CGSize(width: 640, height: 480),
            antialiasingMode: .multisampling4X
        )
        guard let jpegData = image.jpegData(compressionQuality: 0.82) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try jpegData.write(to: destination, options: .atomic)
    }
}

@available(iOS 16.0, *)
private enum RoomPlanCaptureError: LocalizedError {
    case missingCapturedRoom
    case invalidExport

    var errorDescription: String? {
        switch self {
        case .missingCapturedRoom:
            String(localized: "scanning.error.missing_capture")
        case .invalidExport:
            String(localized: "scanning.error.invalid_export")
        }
    }
}
#endif
