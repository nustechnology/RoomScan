//
//  ViewerViewModelNoteOperationTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import simd
import Testing

@MainActor
struct ViewerViewModelNoteOperationTests {
    @Test func selectNoteFocusesCamera() async throws {
        let viewModel = await ViewerViewModelTestHelpers.loadedViewModel(scanID: "scan-focus")
        let note = try #require(viewModel.notes.first)

        viewModel.selectNote(id: note.id)

        #expect(viewModel.selectedNoteID == note.id)
        #expect(viewModel.cameraCommands.map(\.command) == [.focus(note.position)])
    }

    @Test func selectingAnotherNoteCancelsThePreviousDetailFetch() async throws {
        let notesService = CancellableDetailNotesService()
        let viewModel = ViewerViewModel(
            input: ViewerInput(scanID: "scan-selection", scanName: "Room"),
            notesService: notesService,
            modelLoadingService: TestModelLoadingService()
        )
        await viewModel.load()
        let first = try #require(viewModel.notes.first)
        let second = try #require(viewModel.notes.last)

        viewModel.selectNote(id: first.id)
        await notesService.waitUntilDetailFetchStarted()
        viewModel.selectNote(id: second.id)

        await notesService.waitUntilDetailFetchCancelled()
        #expect(notesService.cancelledNoteIDs == [first.id])
        #expect(viewModel.selectedNoteID == second.id)
    }

    @Test func confirmDeleteRemovesNote() async throws {
        let viewModel = await ViewerViewModelTestHelpers.loadedViewModel(scanID: "scan-delete")
        let note = try #require(viewModel.notes.first)
        let remaining = viewModel.notes.count - 1

        viewModel.requestDelete(note)
        await viewModel.confirmDelete(note)

        #expect(viewModel.notes.count == remaining)
        #expect(viewModel.notes.contains(where: { $0.id == note.id }) == false)
        #expect(viewModel.notePendingDeletion == nil)
    }

    @Test func moveNoteUpdatesPosition() async throws {
        let viewModel = await ViewerViewModelTestHelpers.loadedViewModel(scanID: "scan-move")
        let note = try #require(viewModel.notes.first)
        let newPosition = SIMD3<Float>(-0.4, 1.2, 0.8)

        viewModel.beginMoveNote(note)
        viewModel.updateMoveDraft(position: newPosition)
        viewModel.confirmPlacement()
        await ViewerViewModelTestHelpers.waitUntilIdle(viewModel)

        let updated = try #require(viewModel.notes.first(where: { $0.id == note.id }))
        #expect(updated.position == newPosition)
        #expect(viewModel.placementMode == .idle)
    }

    @Test func reportModelLoadFailedSetsFailedState() async {
        let viewModel = await ViewerViewModelTestHelpers.loadedViewModel(scanID: "scan-model-fail")

        viewModel.reportModelLoadFailed()

        #expect(viewModel.loadState == .failed(.loadFailed))
    }

    @Test func saveFailureKeepsEditorOpenAndReturnsFalse() async {
        let notesService = FailingNotesService(seedCount: 0)
        notesService.failingOperations = [.create]
        let viewModel = ViewerViewModel(
            input: ViewerInput(scanID: "scan-save-fail", scanName: "Room"),
            notesService: notesService,
            modelLoadingService: TestModelLoadingService()
        )
        await viewModel.load()
        viewModel.beginAddNote()
        viewModel.handleCanvasTap(position: SIMD3(1, 1, 1))
        viewModel.confirmPlacement()

        let didSave = await viewModel.saveEditor(
            title: "Outlet",
            description: "Needs cover",
            color: .red
        )

        #expect(didSave == false)
        #expect(viewModel.editorMode != nil)
        #expect(viewModel.notes.isEmpty)
    }

    @Test func saveRejectedWhileBusy() async {
        let notesService = GatedNotesService()
        let viewModel = ViewerViewModel(
            input: ViewerInput(scanID: "scan-double-save", scanName: "Room"),
            notesService: notesService,
            modelLoadingService: TestModelLoadingService()
        )
        await viewModel.load()
        viewModel.beginAddNote()
        viewModel.handleCanvasTap(position: SIMD3(1, 1, 1))
        viewModel.confirmPlacement()

        let firstTask = Task {
            await viewModel.saveEditor(
                title: "First",
                description: "One",
                color: .blue
            )
        }

        await notesService.waitUntilCreateStarted()
        #expect(viewModel.isBusy)

        let second = await viewModel.saveEditor(
            title: "Second",
            description: "Two",
            color: .green
        )
        #expect(second == false)

        notesService.releaseCreate()
        let first = await firstTask.value
        #expect(first == true)
        #expect(viewModel.notes.count == 2)
        #expect(viewModel.notes.contains(where: { $0.title == "First" }))
    }

    @Test func deleteFailureClearsPendingNoteAndSurfacesError() async throws {
        let notesService = FailingNotesService(seedCount: 1)
        notesService.failingOperations = [.delete]
        let viewModel = ViewerViewModel(
            input: ViewerInput(scanID: "scan-delete-fail", scanName: "Room"),
            notesService: notesService,
            modelLoadingService: TestModelLoadingService()
        )
        await viewModel.load()
        let note = try #require(viewModel.notes.first)

        viewModel.requestDelete(note)
        await viewModel.confirmDelete(note)

        #expect(viewModel.notePendingDeletion == nil)
        #expect(viewModel.notes.count == 1)
        #expect(viewModel.showsOperationError)
        #expect(viewModel.operationErrorMessage != nil)
    }

    @Test func moveFailureSurfacesErrorAndLeavesNoteInPlace() async throws {
        let notesService = FailingNotesService(seedCount: 1)
        notesService.failingOperations = [.move]
        let viewModel = ViewerViewModel(
            input: ViewerInput(scanID: "scan-move-fail", scanName: "Room"),
            notesService: notesService,
            modelLoadingService: TestModelLoadingService()
        )
        await viewModel.load()
        let note = try #require(viewModel.notes.first)
        let originalPosition = note.position

        viewModel.beginMoveNote(note)
        viewModel.updateMoveDraft(position: SIMD3(9, 9, 9))
        viewModel.confirmPlacement()
        await ViewerViewModelTestHelpers.waitUntilIdle(viewModel)

        let updated = try #require(viewModel.notes.first(where: { $0.id == note.id }))
        #expect(updated.position == originalPosition)
        #expect(viewModel.placementMode == .idle)
        #expect(viewModel.showsOperationError)
    }

    @Test func moveIgnoredWhileBusy() async throws {
        let notesService = DelayedNotesService(delayNanoseconds: 80_000_000)
        let viewModel = ViewerViewModel(
            input: ViewerInput(scanID: "scan-move-busy", scanName: "Room"),
            notesService: notesService,
            modelLoadingService: TestModelLoadingService()
        )
        await viewModel.load()
        let note = try #require(viewModel.notes.first)

        viewModel.beginMoveNote(note)
        viewModel.updateMoveDraft(position: SIMD3(1, 1, 1))
        viewModel.confirmPlacement()
        // Second confirm while first move is in flight should be ignored.
        try? await Task.sleep(nanoseconds: 10_000_000)
        viewModel.beginMoveNote(note)
        viewModel.updateMoveDraft(position: SIMD3(2, 2, 2))
        viewModel.confirmPlacement()
        await ViewerViewModelTestHelpers.waitUntilIdle(viewModel)

        let updated = try #require(viewModel.notes.first(where: { $0.id == note.id }))
        #expect(updated.position == SIMD3(1, 1, 1))
        #expect(notesService.moveCallCount == 1)
    }
}
