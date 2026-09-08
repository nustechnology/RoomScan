//
//  ViewerViewModelTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import simd
import Testing

@MainActor
struct ViewerViewModelTests {
    @Test func loadFetchesModelAndNotes() async {
        let notesService = MockNotesService()
        let viewModel = ViewerViewModel(
            input: ViewerInput(scanID: "scan-1", scanName: "Living Room"),
            notesService: notesService,
            modelLoadingService: DefaultModelLoadingService()
        )

        await viewModel.load()

        #expect(viewModel.loadState == .failed(.fileNotFound))
        #expect(viewModel.notes.isEmpty)
        #expect(viewModel.viewMode == .threeD)
    }

    @Test func canShareMatchesScanShareReadiness() {
        let pending = ViewerViewModel(
            input: ViewerInput(
                scanID: "scan-pending",
                scanName: "Living Room",
                syncStatus: .pending
            ),
            notesService: MockNotesService(),
            modelLoadingService: DefaultModelLoadingService()
        )
        let uploaded = ViewerViewModel(
            input: ViewerInput(
                scanID: "scan-uploaded",
                scanName: "Living Room",
                syncStatus: .pending,
                assetStatus: "UPLOADED"
            ),
            notesService: MockNotesService(),
            modelLoadingService: DefaultModelLoadingService()
        )
        let synced = ViewerViewModel(
            input: ViewerInput(
                scanID: "scan-synced",
                scanName: "Living Room",
                syncStatus: .synced
            ),
            notesService: MockNotesService(),
            modelLoadingService: DefaultModelLoadingService()
        )

        #expect(!pending.canShare)
        #expect(uploaded.canShare)
        #expect(synced.canShare)
    }

    @Test func loadShowsNotesLoadingWhileFetchingNotes() async {
        let notesService = DelayedNotesService(
            delayNanoseconds: 80_000_000,
            shouldBlockFetchUntilReleased: true
        )
        let viewModel = ViewerViewModel(
            input: ViewerInput(scanID: "scan-loading", scanName: "Living Room"),
            notesService: notesService,
            modelLoadingService: TestModelLoadingService()
        )

        let loadTask = Task { await viewModel.load() }
        await notesService.waitUntilFetchNotesStarted()

        #expect(viewModel.isLoadingNotes)
        notesService.releaseFetchNotes()
        await loadTask.value
        #expect(!viewModel.isLoadingNotes)
    }

    @Test func renameScanUpdatesTitle() async {
        let viewModel = ViewerViewModel(
            input: ViewerInput(scanID: "scan-1", scanName: "Living Room"),
            notesService: MockNotesService(),
            modelLoadingService: DefaultModelLoadingService(),
            modelDownloadService: ScanDetailVersionStub()
        )

        let updatedDetail = await viewModel.renameScan(to: "  Dining Room  ")

        #expect(updatedDetail?.name == "Kitchen")
        #expect(viewModel.scanTitle == "Kitchen")
    }

    @Test func renameScanRejectsEmptyName() async {
        let viewModel = ViewerViewModel(
            input: ViewerInput(scanID: "scan-1", scanName: "Living Room"),
            notesService: MockNotesService(),
            modelLoadingService: DefaultModelLoadingService()
        )

        let updatedDetail = await viewModel.renameScan(to: "   ")

        #expect(updatedDetail?.name == nil)
        #expect(viewModel.scanTitle == "Living Room")
        #expect(viewModel.operationErrorMessage == String(localized: "viewer.scan.rename.error"))
    }

    @Test func renameScanFailureSurfacesErrorAndPreservesTitle() async {
        let viewModel = ViewerViewModel(
            input: ViewerInput(scanID: "scan-1", scanName: "Living Room"),
            notesService: MockNotesService(),
            modelLoadingService: DefaultModelLoadingService(),
            modelDownloadService: FailingScanDetailRenameStub()
        )

        let updatedDetail = await viewModel.renameScan(to: "Kitchen")

        #expect(updatedDetail == nil)
        #expect(viewModel.scanTitle == "Living Room")
        #expect(viewModel.operationErrorMessage == String(localized: "viewer.scan.rename.error"))
    }

    @Test func renameScanCancellationDoesNotSurfaceError() async {
        let viewModel = ViewerViewModel(
            input: ViewerInput(scanID: "scan-1", scanName: "Living Room"),
            notesService: MockNotesService(),
            modelLoadingService: DefaultModelLoadingService(),
            modelDownloadService: CancelledScanDetailRenameStub()
        )

        let updatedDetail = await viewModel.renameScan(to: "Kitchen")

        #expect(updatedDetail == nil)
        #expect(viewModel.scanTitle == "Living Room")
        #expect(viewModel.operationErrorMessage == nil)
    }

    @Test func renameScanWithoutDetailServiceSurfacesError() async {
        let viewModel = ViewerViewModel(
            input: ViewerInput(scanID: "scan-1", scanName: "Living Room"),
            notesService: MockNotesService(),
            modelLoadingService: DefaultModelLoadingService()
        )

        let updatedDetail = await viewModel.renameScan(to: "Kitchen")

        #expect(updatedDetail == nil)
        #expect(viewModel.scanTitle == "Living Room")
        #expect(viewModel.operationErrorMessage == String(localized: "viewer.scan.rename.error"))
    }

    @Test func switchingViewModeKeepsNotes() async {
        let viewModel = await ViewerViewModelTestHelpers.loadedViewModel(scanID: "scan-mode")
        let noteCount = viewModel.notes.count

        viewModel.setViewMode(.topView)

        #expect(viewModel.viewMode == .topView)
        #expect(viewModel.notes.count == noteCount)
    }

    @Test func beginAddNoteEntersPlacementMode() async {
        let viewModel = await ViewerViewModelTestHelpers.loadedViewModel(scanID: "scan-place")

        viewModel.beginAddNote()

        #expect(viewModel.placementMode == .placingNew)
        #expect(viewModel.isPlacementActive)
    }

    @Test func surfaceTapInPlacementPreparesDraftUntilDone() async {
        let viewModel = await ViewerViewModelTestHelpers.loadedViewModel(scanID: "scan-create")
        viewModel.beginAddNote()

        viewModel.handleCanvasTap(position: SIMD3(0.5, 1.0, -0.2))

        #expect(viewModel.placementMode == .placingNew)
        #expect(viewModel.placementDraftPosition == SIMD3(0.5, 1.0, -0.2))
        #expect(viewModel.editorMode == nil)

        viewModel.confirmPlacement()

        #expect(viewModel.placementMode == .idle)
        guard case .create(let position) = viewModel.editorMode else {
            Issue.record("Expected create editor mode")
            return
        }
        #expect(position == SIMD3(0.5, 1.0, -0.2))
    }

    @Test func saveCreateAddsNote() async {
        let notesService = MockNotesService()
        let viewModel = ViewerViewModel(
            input: ViewerInput(scanID: "scan-save", scanName: "Kitchen"),
            notesService: notesService,
            modelLoadingService: TestModelLoadingService()
        )
        await viewModel.load()
        let initialCount = viewModel.notes.count
        viewModel.handleCanvasTap(position: .zero) // no-op while idle
        viewModel.beginAddNote()
        viewModel.handleCanvasTap(position: SIMD3(1, 1, 1))
        viewModel.confirmPlacement()

        let didSave = await viewModel.saveEditor(
            title: "Outlet",
            description: "Needs cover plate",
            color: .green
        )

        #expect(didSave)
        #expect(viewModel.notes.count == initialCount + 1)
        #expect(viewModel.notes.last?.title == "Outlet")
        #expect(viewModel.notes.last?.color == .green)
        #expect(viewModel.editorMode == nil)
    }

    @Test func saveCreateUsesScanModelVersionWhenThereAreNoExistingNotes() async {
        let notesService = FailingNotesService(seedCount: 0)
        let viewModel = ViewerViewModel(
            input: ViewerInput(
                scanID: "scan-first-note",
                scanName: "Kitchen",
                modelVersion: "7"
            ),
            notesService: notesService,
            modelLoadingService: TestModelLoadingService()
        )
        await viewModel.load()
        viewModel.beginAddNote()
        viewModel.handleCanvasTap(position: SIMD3(1, 1, 1))
        viewModel.confirmPlacement()

        let didSave = await viewModel.saveEditor(
            title: "Outlet",
            description: "Needs cover plate",
            color: .green
        )

        #expect(didSave)
        #expect(viewModel.notes.count == 1)
        #expect(viewModel.notes.first?.modelVersion == "7")
    }

    @Test func saveCreateLoadsScanModelVersionWhenViewerOpenedBeforeDetail() async {
        let notesService = FailingNotesService(seedCount: 0)
        let viewModel = ViewerViewModel(
            input: ViewerInput(scanID: "scan-first-note", scanName: "Kitchen"),
            notesService: notesService,
            modelLoadingService: TestModelLoadingService(),
            modelDownloadService: ScanDetailVersionStub()
        )
        await viewModel.load()
        viewModel.beginAddNote()
        viewModel.handleCanvasTap(position: SIMD3(1, 1, 1))
        viewModel.confirmPlacement()

        let didSave = await viewModel.saveEditor(
            title: "Outlet",
            description: "Needs cover plate",
            color: .green
        )

        #expect(didSave)
        #expect(viewModel.notes.first?.modelVersion == "1")
    }

    @Test func saveCreatePrefersScanDetailVersionOverExistingNotes() async {
        let notesService = FailingNotesService(seedCount: 1)
        let viewModel = ViewerViewModel(
            input: ViewerInput(scanID: "scan-current-version", scanName: "Kitchen"),
            notesService: notesService,
            modelLoadingService: TestModelLoadingService(),
            modelDownloadService: ScanDetailVersionStub()
        )
        await viewModel.load()
        viewModel.beginAddNote()
        viewModel.handleCanvasTap(position: SIMD3(1, 1, 1))
        viewModel.confirmPlacement()

        let didSave = await viewModel.saveEditor(
            title: "Outlet",
            description: "Needs cover plate",
            color: .green
        )

        #expect(didSave)
        #expect(viewModel.notes.last?.modelVersion == "1")
    }
}
