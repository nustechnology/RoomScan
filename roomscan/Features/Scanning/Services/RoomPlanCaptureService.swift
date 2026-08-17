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
        }
    }

    func startSession() {
        isScanning = true
        hasMinimalStructure = false
        isStorageFull = false
        isSessionPendingStart = true
        isPaused = false
        pausedARConfiguration = nil
        hasRecordedFirstFrame = false
        lastStorageCheckDate = nil
        isCheckingStorage = false
        finalCapturedRoomData = nil
        captureEndError = nil

        if let session = roomCaptureSession {
            let config = RoomCaptureSession.Configuration()
            session.run(configuration: config)
            ScanTelemetry.shared.recordSessionRunCalled()
            isSessionPendingStart = false
            isCaptureSessionRunning = true
        }
    }

    func pauseSession() {
        guard isCaptureSessionRunning, !isPaused, let arSession = roomCaptureSession?.arSession else { return }
        pausedARConfiguration = arSession.configuration
        arSession.pause()
        isPaused = true
        isScanning = false
    }

    func resumeSession() {
        guard isCaptureSessionRunning, isPaused, let arSession = roomCaptureSession?.arSession else { return }
        // Resuming must restart the ARSession that `pauseSession` paused. Re-running the
        // RoomCaptureSession leaves the AR session paused and also discards the in-progress scan.
        guard let configuration = pausedARConfiguration ?? arSession.configuration else {
            return
        }
        arSession.run(configuration)
        pausedARConfiguration = nil
        isPaused = false
        isScanning = true
    }

    func stopSession() {
        guard isCaptureSessionRunning || isSessionPendingStart else { return }
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
        stopSession()

        for _ in 0..<100 where finalCapturedRoomData == nil && captureEndError == nil {
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

        let roomToExport = capturedRoom
        let exportURL = meshURL
        try await Task.detached(priority: .userInitiated) {
            // `.model` substitutes object bounding boxes with catalog meshes. Scan-time
            // RoomCaptureView still draws parametric boxes; that overlay is unchanged.
            if #available(iOS 17.0, *) {
                let modelProvider = try RoomPlanModelCatalog.makeProvider()
                try roomToExport.export(
                    to: exportURL,
                    modelProvider: modelProvider,
                    exportOptions: .model
                )
            } else {
                try roomToExport.export(to: exportURL, exportOptions: .mesh)
            }
        }.value

        let meshSize = (try? FileManager.default.attributesOfItem(atPath: meshURL.path)[.size] as? Int64) ?? 0
        guard meshSize > 0 else {
            throw RoomPlanCaptureError.invalidExport
        }

        do {
            try await Task.detached(priority: .utility) {
                try Self.generateThumbnail(from: meshURL, destination: thumbnailURL)
            }.value
        } catch {
            try generateFallbackThumbnail(destination: thumbnailURL)
        }

        let draft = RoomScanDraft(id: draftID, meshFileURL: meshURL, thumbnailFileURL: thumbnailURL)
        do {
            try storageService.saveDraftManifest(draft)
        } catch {
            ScanTelemetry.shared.recordDraftManifestSaveFailed(error)
        }
        return draft
    }

    private var hasRecordedFirstFrame = false
    private var lastStorageCheckDate: Date?
    private var isCheckingStorage = false
    nonisolated private static let midScanStorageCheckInterval: TimeInterval = 5
    nonisolated private static let midScanMinimumAvailableBytes: Int64 = 50_000_000

    // MARK: - RoomCaptureSessionDelegate
    nonisolated func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        Task { @MainActor in
            if !self.hasRecordedFirstFrame {
                self.hasRecordedFirstFrame = true
                ScanTelemetry.shared.recordFirstFrameReceived()
            }
            self.currentCapturedRoom = room
            let hasStructure = !room.walls.isEmpty && !room.floors.isEmpty
            if hasStructure && !self.hasMinimalStructure {
                self.hasMinimalStructure = true
            }
            self.scheduleMidScanStorageCheckIfNeeded()
        }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.currentInstruction = Self.localizedInstruction(for: instruction)
        }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: (any Error)?) {
        Task { @MainActor in
            self.isScanning = false
            self.finalCapturedRoomData = data
            self.captureEndError = error
        }
    }
}

@available(iOS 16.0, *)
private extension RoomPlanCaptureService {
    nonisolated static func localizedInstruction(
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

    func scheduleMidScanStorageCheckIfNeeded() {
        guard !isCheckingStorage else { return }

        let now = Date()
        if let lastStorageCheckDate,
           now.timeIntervalSince(lastStorageCheckDate) < Self.midScanStorageCheckInterval {
            return
        }

        lastStorageCheckDate = now
        isCheckingStorage = true

        Task { [weak self] in
            let isFull = await Self.isStorageBelowMinimumCapacity()
            guard let self else { return }
            self.isCheckingStorage = false
            guard isFull, self.isCaptureSessionRunning || self.isSessionPendingStart else { return }
            self.isStorageFull = true
            self.stopSession()
        }
    }

    nonisolated static func isStorageBelowMinimumCapacity() async -> Bool {
        let minimumBytes = midScanMinimumAvailableBytes
        return await Task.detached(priority: .utility) {
            do {
                let values = try FileManager.default.url(
                    for: .documentDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: false
                ).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])

                guard let availableBytes = values.volumeAvailableCapacityForImportantUsage else {
                    return false
                }
                return availableBytes < minimumBytes
            } catch {
                return false
            }
        }.value
    }

    func roomForExport() async throws -> CapturedRoom {
        let processedRoom = await processedRoomFromFinalData()

        let source = CapturedRoomExportSelection.preferredSource(
            processed: processedRoom.map(contentSummary(of:)),
            live: currentCapturedRoom.map(contentSummary(of:))
        )

        switch source {
        case .processed:
            guard let processedRoom else {
                throw RoomPlanCaptureError.missingCapturedRoom
            }
            return processedRoom
        case .live:
            guard let currentCapturedRoom else {
                throw RoomPlanCaptureError.missingCapturedRoom
            }
            return currentCapturedRoom
        case nil:
            throw RoomPlanCaptureError.missingCapturedRoom
        }
    }

    func processedRoomFromFinalData() async -> CapturedRoom? {
        guard let finalCapturedRoomData else { return nil }
        do {
            return try await RoomBuilder(options: [])
                .capturedRoom(from: finalCapturedRoomData)
        } catch {
            return nil
        }
    }

    func contentSummary(of room: CapturedRoom) -> CapturedRoomContentSummary {
        CapturedRoomContentSummary(
            wallCount: room.walls.count,
            floorCount: room.floors.count,
            doorCount: room.doors.count,
            windowCount: room.windows.count,
            openingCount: room.openings.count,
            objectCount: room.objects.count
        )
    }

    func generateFallbackThumbnail(destination: URL) throws {
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

    nonisolated static func generateThumbnail(from meshURL: URL, destination: URL) throws {
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
