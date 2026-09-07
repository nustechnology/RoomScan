//
//  CameraScanViewModel.swift
//  roomscan
//

import Combine
import Foundation
import UIKit

@MainActor
final class CameraScanViewModel: ObservableObject {
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var hasMinimalStructure: Bool = false
    @Published private(set) var isPaused: Bool = false
    @Published var showCancelConfirmation: Bool = false
    @Published var showTrackingLostAlert: Bool = false
    @Published var showFinishError: Bool = false
    @Published private(set) var isStorageFull: Bool = false
    @Published private(set) var isProcessingFinish: Bool = false
    @Published private(set) var capturedDraft: RoomScanDraft?
    @Published private(set) var currentInstruction: String?
    @Published var errorMessage: String?

    let sourceProjectID: String?
    let captureService: RoomCaptureService
    private let storageService: ScanStorageService
    private var cancellables = Set<AnyCancellable>()
    private var previousIdleTimerDisabled: Bool?

    init(
        sourceProjectID: String? = nil,
        captureService: RoomCaptureService? = nil,
        storageService: ScanStorageService = LocalScanStorageService()
    ) {
        self.sourceProjectID = sourceProjectID
        self.captureService = captureService ?? RoomCaptureServiceFactory.makeService()
        self.storageService = storageService
        setupPublishers()
    }

    private func setupPublishers() {
        captureService.minimalStructurePublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$hasMinimalStructure)

        captureService.storageFullPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] full in
                guard let self = self else { return }
                self.isStorageFull = full
                if full {
                    self.errorMessage = String(localized: "scanning.error.storage_full")
                    self.stopScanning()
                }
            }
            .store(in: &cancellables)

        captureService.instructionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] instruction in
                self?.currentInstruction = instruction
            }
            .store(in: &cancellables)

        captureService.sessionEndedUnexpectedlyPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.handleUnexpectedSessionEnd()
            }
            .store(in: &cancellables)
    }

    func startScanning() {
        guard !isScanning else { return }
        checkStorageSpace()
        guard !isStorageFull else { return }

        isScanning = true
        isPaused = false
        showTrackingLostAlert = false
        showFinishError = false
        errorMessage = nil
        if previousIdleTimerDisabled == nil {
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        }
        UIApplication.shared.isIdleTimerDisabled = true
        captureService.startSession()
    }

    func stopScanning() {
        isScanning = false
        isPaused = false
        if let previousIdleTimerDisabled {
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
            self.previousIdleTimerDisabled = nil
        }
        captureService.stopSession()
    }

    func handleCancelTapped() {
        guard isScanning, !isProcessingFinish else { return }
        captureService.pauseSession()
        isPaused = true
        showCancelConfirmation = true
    }

    func resumeScanning() {
        showCancelConfirmation = false
        guard isScanning else { return }
        captureService.resumeSession()
        isPaused = false
    }

    func togglePause() {
        guard isScanning else { return }
        if isPaused {
            captureService.resumeSession()
            isPaused = false
        } else {
            captureService.pauseSession()
            isPaused = true
        }
    }

    func discardAndExit() {
        showCancelConfirmation = false
        storageService.clearDraftManifest()
        stopScanning()
    }

    func finishScan() async -> RoomScanDraft? {
        guard hasMinimalStructure, !isProcessingFinish else {
            return nil
        }
        isProcessingFinish = true
        defer {
            isProcessingFinish = false
            stopScanning()
        }

        do {
            var draft = try await captureService.finishScan()
            draft.projectID = sourceProjectID

            let meshSize = (try? FileManager.default.attributesOfItem(atPath: draft.meshFileURL.path)[.size] as? Int64) ?? 0
            guard meshSize > 0 else {
                throw CocoaError(.fileReadCorruptFile)
            }

            try storageService.saveDraftManifest(draft)
            self.capturedDraft = draft
            return draft
        } catch {
            self.errorMessage = error.localizedDescription
            self.showFinishError = true
            return nil
        }
    }

    func retryAfterStorageFull() {
        showCancelConfirmation = false
        isStorageFull = false
        errorMessage = nil
        checkStorageSpace()
        guard !isStorageFull else { return }
        startScanning()
    }

    func retryAfterTrackingLost() {
        showTrackingLostAlert = false
        errorMessage = nil
        startScanning()
    }

    private func handleUnexpectedSessionEnd() {
        guard !isProcessingFinish, !isPaused else { return }
        showCancelConfirmation = false
        isPaused = false

        guard hasMinimalStructure else {
            errorMessage = String(localized: "scanning.error.tracking_lost")
            showTrackingLostAlert = true
            stopScanning()
            return
        }

        Task {
            _ = await finishScan()
        }
    }

    private func checkStorageSpace() {
        do {
            let values = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            ).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])

            if let availableBytes = values.volumeAvailableCapacityForImportantUsage, availableBytes < 50_000_000 { // < 50MB
                isStorageFull = true
                errorMessage = String(localized: "scanning.error.storage_full")
            } else {
                isStorageFull = false
                if errorMessage == String(localized: "scanning.error.storage_full") {
                    errorMessage = nil
                }
            }
        } catch {
            // Ignore error if capacity check fails
        }
    }

    deinit {
        let idleTimerValueToRestore = previousIdleTimerDisabled
        Task { @MainActor in
            if let idleTimerValueToRestore {
                UIApplication.shared.isIdleTimerDisabled = idleTimerValueToRestore
            }
        }
    }
}
