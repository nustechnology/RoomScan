//
//  RoomCaptureService.swift
//  roomscan
//

import Combine
import Foundation
import UIKit

@MainActor
protocol RoomCaptureService: AnyObject {
    var isScanning: Bool { get }
    var hasMinimalStructure: Bool { get }
    var isStorageFull: Bool { get }
    var currentInstruction: String? { get }

    var minimalStructurePublisher: AnyPublisher<Bool, Never> { get }
    var storageFullPublisher: AnyPublisher<Bool, Never> { get }
    var instructionPublisher: AnyPublisher<String?, Never> { get }
    var sessionEndedUnexpectedlyPublisher: AnyPublisher<Void, Never> { get }

    func startSession()
    func pauseSession()
    func resumeSession()
    func stopSession()
    func finishScan() async throws -> RoomScanDraft
}

@MainActor
final class MockRoomCaptureService: RoomCaptureService {
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var hasMinimalStructure: Bool = false
    @Published private(set) var isStorageFull: Bool = false
    @Published private(set) var currentInstruction: String?

    private let simulateStructureDelay: TimeInterval
    private var timer: Timer?
    private var isSessionActive = false
    private var isPaused = false
    private var isWaitingForStopCallback = false
    private var isStartQueued = false
    private var shouldDeferNextStopCallback = false
    private let sessionEndedUnexpectedlySubject = PassthroughSubject<Void, Never>()

    private(set) var stopCallCount = 0

    var minimalStructurePublisher: AnyPublisher<Bool, Never> {
        $hasMinimalStructure.eraseToAnyPublisher()
    }

    var storageFullPublisher: AnyPublisher<Bool, Never> {
        $isStorageFull.eraseToAnyPublisher()
    }

    var instructionPublisher: AnyPublisher<String?, Never> {
        $currentInstruction.eraseToAnyPublisher()
    }

    var sessionEndedUnexpectedlyPublisher: AnyPublisher<Void, Never> {
        sessionEndedUnexpectedlySubject.eraseToAnyPublisher()
    }

    private let storageService: ScanStorageService?

    init(simulateStructureDelay: TimeInterval? = nil, storageService: ScanStorageService? = nil) {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-UITesting")
        self.simulateStructureDelay = simulateStructureDelay ?? (isUITesting ? 0.1 : 1.5)
        self.storageService = storageService
    }

    func startSession() {
        if isWaitingForStopCallback {
            isStartQueued = true
            isScanning = true
            isPaused = false
            hasMinimalStructure = false
            isStorageFull = false
            return
        }
        beginSession()
    }

    private func beginSession() {
        isScanning = true
        isSessionActive = true
        isPaused = false
        isWaitingForStopCallback = false
        isStartQueued = false
        hasMinimalStructure = false
        isStorageFull = false
        ScanTelemetry.shared.recordSessionRunCalled()
        startStructureTimer()
    }

    func deferNextStopTerminalCallback() {
        shouldDeferNextStopCallback = true
    }

    func simulateStaleSessionEnd() {
        guard isWaitingForStopCallback else { return }
        isWaitingForStopCallback = false
        guard isStartQueued else { return }
        isStartQueued = false
        beginSession()
    }

    func stopSession() {
        guard isSessionActive || isStartQueued || isWaitingForStopCallback else { return }
        if isSessionActive {
            stopCallCount += 1
        }
        isSessionActive = false
        isScanning = false
        isPaused = false
        timer?.invalidate()
        timer = nil

        if shouldDeferNextStopCallback {
            shouldDeferNextStopCallback = false
            isWaitingForStopCallback = true
            return
        }

        isWaitingForStopCallback = false
        isStartQueued = false
    }

    func pauseSession() {
        guard isSessionActive, isScanning else { return }
        isScanning = false
        isPaused = true
        timer?.invalidate()
        timer = nil
    }

    func resumeSession() {
        guard isSessionActive, isPaused else { return }
        isPaused = false
        isScanning = true
        if !hasMinimalStructure {
            startStructureTimer()
        }
    }

    func simulateUnexpectedSessionEnd() {
        guard isSessionActive else { return }
        if isPaused {
            sessionEndedUnexpectedlySubject.send()
            return
        }
        isSessionActive = false
        isScanning = false
        timer?.invalidate()
        timer = nil
        sessionEndedUnexpectedlySubject.send()
    }

    private func startStructureTimer() {
        timer?.invalidate()
        if simulateStructureDelay > 0 {
            timer = Timer.scheduledTimer(withTimeInterval: simulateStructureDelay, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    ScanTelemetry.shared.recordFirstFrameReceived()
                    self?.hasMinimalStructure = true
                }
            }
        } else {
            ScanTelemetry.shared.recordFirstFrameReceived()
            hasMinimalStructure = true
        }
    }

    func setStorageFullForTesting(_ full: Bool) {
        isStorageFull = full
        if full {
            stopSession()
        }
    }

    func finishScan() async throws -> RoomScanDraft {
        stopSession()

        let draftID = UUID().uuidString
        let draftDirectory = try LocalScanStorageService.makeCaptureDraftDirectory(id: draftID)
        let meshURL = draftDirectory.appendingPathComponent("room_mesh.usdz")
        let thumbnailURL = draftDirectory.appendingPathComponent("thumbnail.jpg")

        // Create empty mock files
        let dummyMeshContent = Data("Mock USDZ Data".utf8)
        let dummyThumbContent = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 480))
            .jpegData(withCompressionQuality: 0.82) { context in
                UIColor.systemGray5.setFill()
                context.cgContext.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
            }

        try dummyMeshContent.write(to: meshURL)
        try dummyThumbContent.write(to: thumbnailURL)

        return RoomScanDraft(
            id: draftID,
            meshFileURL: meshURL,
            thumbnailFileURL: thumbnailURL
        )
    }
}
