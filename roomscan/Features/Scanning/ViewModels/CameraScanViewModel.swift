//
//  CameraScanViewModel.swift
//  roomscan
//

import Foundation
import Combine
import UIKit

@MainActor
final class CameraScanViewModel: ObservableObject {
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var hasMinimalStructure: Bool = false
    @Published var showCancelConfirmation: Bool = false
    @Published private(set) var isStorageFull: Bool = false
    @Published private(set) var isProcessingFinish: Bool = false
    @Published private(set) var capturedDraft: RoomScanDraft?
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
                }
            }
            .store(in: &cancellables)
    }

    func startScanning() {
        guard !isScanning else { return }
        checkStorageSpace()
        guard !isStorageFull else { return }

        isScanning = true
        if previousIdleTimerDisabled == nil {
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        }
        UIApplication.shared.isIdleTimerDisabled = true
        captureService.startSession()
    }

    func stopScanning() {
        isScanning = false
        if let previousIdleTimerDisabled {
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
            self.previousIdleTimerDisabled = nil
        }
        captureService.stopSession()
    }

    func handleCancelTapped() {
        guard isScanning else { return }
        captureService.pauseSession()
        showCancelConfirmation = true
    }

    func resumeScanning() {
        showCancelConfirmation = false
        guard isScanning else { return }
        captureService.resumeSession()
    }

    func discardAndExit() {
        showCancelConfirmation = false
        stopScanning()
    }

    func finishScan() async -> RoomScanDraft? {
        print("[RoomScan STEP 2] CameraScanViewModel.finishScan() entered")
        guard hasMinimalStructure, !isProcessingFinish else {
            print("[RoomScan STEP 2-CANCEL] guard failed: hasMinimalStructure=\(hasMinimalStructure), isProcessingFinish=\(isProcessingFinish)")
            return nil
        }
        isProcessingFinish = true
        defer {
            isProcessingFinish = false
            stopScanning()
        }

        do {
            print("[RoomScan STEP 3] Calling captureService.finishScan()...")
            var draft = try await captureService.finishScan()
            print("[RoomScan STEP 4] captureService.finishScan() succeeded. Draft ID: \(draft.id)")
            draft.projectID = sourceProjectID

            let meshSize = (try? FileManager.default.attributesOfItem(atPath: draft.meshFileURL.path)[.size] as? Int64) ?? 0
            let thumbSize = (try? FileManager.default.attributesOfItem(atPath: draft.thumbnailFileURL.path)[.size] as? Int64) ?? 0
            guard meshSize > 0 else {
                throw CocoaError(.fileReadCorruptFile)
            }

            try storageService.saveDraftManifest(draft)
            self.capturedDraft = draft

            print("""
            ==================== [ROOMSCAN FINISHED DRAFT DATA] ====================
            ID: \(draft.id)
            Created At: \(draft.createdAt)
            Project ID: \(draft.projectID ?? "None (Standalone)")
            Name: \(draft.name.isEmpty ? "(unnamed)" : draft.name)
            Mesh File URL: \(draft.meshFileURL.path) (\(meshSize) bytes)
            Thumbnail File URL: \(draft.thumbnailFileURL.path) (\(thumbSize) bytes)
            ========================================================================
            """)
            return draft
        } catch {
            print("[RoomScan STEP 3-ERROR] captureService.finishScan() failed with error: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            return nil
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
