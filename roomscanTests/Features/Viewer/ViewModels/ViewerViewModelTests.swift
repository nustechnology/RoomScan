//
//  ViewerViewModelTests.swift
//  roomscanTests
//

import Foundation
import simd
import Testing
@testable import roomscan

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

    @Test func loadShowsNotesLoadingWhileFetchingNotes() async {
        let viewModel = ViewerViewModel(
            input: ViewerInput(scanID: "scan-loading", scanName: "Living Room"),
            notesService: DelayedNotesService(delayNanoseconds: 80_000_000),
            modelLoadingService: TestModelLoadingService()
        )

        let loadTask = Task { await viewModel.load() }
        for _ in 0..<10 where !viewModel.isLoadingNotes {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(viewModel.isLoadingNotes)
        await loadTask.value
        #expect(!viewModel.isLoadingNotes)
    }

    @Test func renameScanUpdatesTitle() {
        let viewModel = ViewerViewModel(
            input: ViewerInput(scanID: "scan-1", scanName: "Living Room"),
            notesService: MockNotesService(),
            modelLoadingService: DefaultModelLoadingService()
        )

        let didRename = viewModel.renameScan(to: "  Dining Room  ")

        #expect(didRename)
        #expect(viewModel.scanTitle == "Dining Room")
    }

    @Test func renameScanRejectsEmptyName() {
        let viewModel = ViewerViewModel(
            input: ViewerInput(scanID: "scan-1", scanName: "Living Room"),
            notesService: MockNotesService(),
            modelLoadingService: DefaultModelLoadingService()
        )

        let didRename = viewModel.renameScan(to: "   ")

        #expect(!didRename)
        #expect(viewModel.scanTitle == "Living Room")
    }

    @Test func switchingViewModeKeepsNotes() async {
        let viewModel = await loadedViewModel(scanID: "scan-mode")
        let noteCount = viewModel.notes.count

        viewModel.setViewMode(.topView)

        #expect(viewModel.viewMode == .topView)
        #expect(viewModel.notes.count == noteCount)
    }

    @Test func beginAddNoteEntersPlacementMode() async {
        let viewModel = await loadedViewModel(scanID: "scan-place")

        viewModel.beginAddNote()

        #expect(viewModel.placementMode == .placingNew)
        #expect(viewModel.isPlacementActive)
    }

    @Test func surfaceTapInPlacementPreparesDraftUntilDone() async {
        let viewModel = await loadedViewModel(scanID: "scan-create")
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

    @Test func selectNoteFocusesCamera() async throws {
        let viewModel = await loadedViewModel(scanID: "scan-focus")
        let note = try #require(viewModel.notes.first)

        viewModel.selectNote(id: note.id)

        #expect(viewModel.selectedNoteID == note.id)
        #expect(viewModel.cameraCommand == .focus(note.position))
    }

    @Test func confirmDeleteRemovesNote() async throws {
        let viewModel = await loadedViewModel(scanID: "scan-delete")
        let note = try #require(viewModel.notes.first)
        let remaining = viewModel.notes.count - 1

        viewModel.requestDelete(note)
        await viewModel.confirmDelete(note)

        #expect(viewModel.notes.count == remaining)
        #expect(viewModel.notes.contains(where: { $0.id == note.id }) == false)
        #expect(viewModel.notePendingDeletion == nil)
    }

    @Test func moveNoteUpdatesPosition() async throws {
        let viewModel = await loadedViewModel(scanID: "scan-move")
        let note = try #require(viewModel.notes.first)
        let newPosition = SIMD3<Float>(-0.4, 1.2, 0.8)

        viewModel.beginMoveNote(note)
        viewModel.updateMoveDraft(position: newPosition)
        viewModel.confirmPlacement()
        await waitUntilIdle(viewModel)

        let updated = try #require(viewModel.notes.first(where: { $0.id == note.id }))
        #expect(updated.position == newPosition)
        #expect(viewModel.placementMode == .idle)
    }

    @Test func reportModelLoadFailedSetsFailedState() async {
        let viewModel = await loadedViewModel(scanID: "scan-model-fail")

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
        await waitUntilIdle(viewModel)

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
        await waitUntilIdle(viewModel)

        let updated = try #require(viewModel.notes.first(where: { $0.id == note.id }))
        #expect(updated.position == SIMD3(1, 1, 1))
        #expect(notesService.moveCallCount == 1)
    }

    private func loadedViewModel(scanID: String) async -> ViewerViewModel {
        let viewModel = ViewerViewModel(
            input: ViewerInput(scanID: scanID, scanName: "Room"),
            notesService: MockNotesService(),
            modelLoadingService: TestModelLoadingService()
        )
        await viewModel.load()
        return viewModel
    }

    private func waitUntilIdle(_ viewModel: ViewerViewModel) async {
        for _ in 0..<50 where viewModel.isBusy {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

@MainActor
struct NoteEditorViewModelTests {
    @Test func truncatesTitleAndDescriptionToLimits() {
        let viewModel = NoteEditorViewModel(mode: .create(position: .zero))
        let longTitle = String(repeating: "a", count: 80)
        let longDescription = String(repeating: "b", count: 2_100)

        viewModel.updateTitle(longTitle)
        viewModel.updateDescription(longDescription)

        #expect(viewModel.title.count == NoteEditorViewModel.titleLimit)
        #expect(viewModel.noteDescription.count == NoteEditorViewModel.descriptionLimit)
    }

    @Test func defaultColorIsYellowForCreate() {
        let viewModel = NoteEditorViewModel(mode: .create(position: .zero))
        #expect(viewModel.color == .yellow)
    }

    @Test func canSaveRequiresNonEmptyFields() {
        let viewModel = NoteEditorViewModel(mode: .create(position: .zero))
        #expect(viewModel.canSave == false)

        viewModel.updateTitle("Crack")
        #expect(viewModel.canSave == false)

        viewModel.updateDescription("Needs repair")
        #expect(viewModel.canSave)
    }

    @Test func canSaveFalseWhileSaving() {
        let viewModel = NoteEditorViewModel(mode: .create(position: .zero))
        viewModel.updateTitle("Crack")
        viewModel.updateDescription("Needs repair")
        viewModel.setSaving(true)

        #expect(viewModel.canSave == false)
    }

    @Test func reportSaveFailedSetsValidationMessage() {
        let viewModel = NoteEditorViewModel(mode: .create(position: .zero))
        viewModel.reportSaveFailed()
        #expect(viewModel.validationMessage != nil)
    }

    @Test func editModePrefillsFields() {
        let note = SpatialNote(
            id: "n1",
            title: "Outlet",
            detail: "Check power",
            color: .blue,
            position: .zero,
                orientation: .zero,
            createdAt: Date(),
            updatedAt: Date(),
            modelVersion: "sample-1"
        )
        let viewModel = NoteEditorViewModel(mode: .edit(note))

        #expect(viewModel.title == "Outlet")
        #expect(viewModel.noteDescription == "Check power")
        #expect(viewModel.color == .blue)
    }
}

@MainActor
struct ModelLoadingServiceTests {
    @Test func explicitSampleURLResolvesToSampleRoom() async throws {
        let service = DefaultModelLoadingService()

        let source = try await service.resolveSource(modelURL: DefaultModelLoadingService.mockSampleURL)

        #expect(source == .sampleRoom)
    }

    @Test func nilURLThrows() async {
        let service = DefaultModelLoadingService()

        do {
            _ = try await service.resolveSource(modelURL: nil)
            Issue.record("Expected fileNotFound")
        } catch let error as ModelLoadingError {
            #expect(error == .fileNotFound)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test func missingFileThrows() async {
        let service = DefaultModelLoadingService()
        let missing = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).usdz")

        do {
            _ = try await service.resolveSource(modelURL: missing)
            Issue.record("Expected fileNotFound")
        } catch let error as ModelLoadingError {
            #expect(error == .fileNotFound)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }
}

// MARK: - Test doubles

private final class TestModelLoadingService: ModelLoadingService {
    func resolveSource(modelURL: URL?) async throws -> ModelSource {
        .sampleRoom
    }
}

private struct ScanDetailVersionStub: ScanDetailService {
    func fetchScanDetail(id: String) async throws -> ScanDetail {
        ScanDetail(
            id: id,
            projectID: "project-1",
            name: "Kitchen",
            description: nil,
            thumbnail: nil,
            creatorID: "user-1",
            creatorEmail: nil,
            noteCount: 0,
            assetStatus: "UPLOADED",
            syncStatus: .synced,
            modelVersion: 1,
            createdAt: .now,
            updatedAt: .now,
            permissions: ScanDetailPermissions(
                role: "OWNER",
                canView: true,
                canEdit: true,
                canDelete: true
            )
        )
    }

    func updateScanDetail(id: String, name: String, description: String?) async throws -> ScanDetail {
        try await fetchScanDetail(id: id)
    }

    func deleteScanDetail(id: String) async throws {}
}

@MainActor
private final class FailingNotesService: NotesService {
    enum Operation {
        case create
        case update
        case move
        case delete
    }

    var failingOperations: Set<Operation> = []
    private var notes: [SpatialNote]
    private let modelVersion = "sample-1"

    init(seedCount: Int) {
        let modelVersion = "sample-1"
        let now = Date()
        notes = (0..<seedCount).map { index in
            SpatialNote(
                id: "seed-\(index)",
                title: "Note \(index)",
                detail: "Detail \(index)",
                color: .yellow,
                position: SIMD3(Float(index), 1, 0),
                orientation: .zero,
                createdAt: now,
                updatedAt: now,
                modelVersion: modelVersion
            )
        }
    }

    func fetchNotes(scanID: String) async throws -> [SpatialNote] {
        notes
    }

    func fetchNote(noteID: String) async throws -> SpatialNote {
        guard let note = notes.first(where: { $0.id == noteID }) else {
            throw NotesServiceError.noteNotFound
        }
        return note
    }

    func createNote(scanID: String, input: CreateNoteInput) async throws -> SpatialNote {
        if failingOperations.contains(.create) {
            throw NotesServiceError.invalidContent
        }
        let now = Date()
        let note = SpatialNote(
            id: UUID().uuidString,
            title: input.title,
            detail: input.description,
            color: input.color,
            position: input.position,
            orientation: input.orientation,
            createdAt: now,
            updatedAt: now,
            modelVersion: input.modelVersion
        )
        notes.append(note)
        return note
    }

    func updateNote(
        scanID: String,
        noteID: String,
        title: String,
        description: String,
        color: NoteColor
    ) async throws -> SpatialNote {
        if failingOperations.contains(.update) {
            throw NotesServiceError.invalidContent
        }
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else {
            throw NotesServiceError.noteNotFound
        }
        notes[index].title = title
        notes[index].detail = description
        notes[index].color = color
        notes[index].updatedAt = Date()
        return notes[index]
    }

    func moveNote(noteID: String, input: MoveNoteInput) async throws -> SpatialNote {
        if failingOperations.contains(.move) {
            throw NotesServiceError.noteNotFound
        }
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else {
            throw NotesServiceError.noteNotFound
        }
        notes[index].position = input.position
        notes[index].orientation = input.orientation
        notes[index].modelVersion = input.modelVersion
        notes[index].updatedAt = Date()
        return notes[index]
    }

    func deleteNote(scanID: String, noteID: String) async throws {
        if failingOperations.contains(.delete) {
            throw NotesServiceError.noteNotFound
        }
        notes.removeAll { $0.id == noteID }
    }
}

@MainActor
private final class GatedNotesService: NotesService {
    private var notes: [SpatialNote]
    private var createStartedContinuation: CheckedContinuation<Void, Never>?
    private var createReleaseContinuation: CheckedContinuation<Void, Never>?
    private var isWaitingForRelease = false
    private let modelVersion = "sample-1"

    init() {
        let now = Date()
        notes = [
            SpatialNote(
                id: "gated-seed",
                title: "Seed",
                detail: "Seed detail",
                color: .yellow,
                position: .zero,
                orientation: .zero,
                createdAt: now,
                updatedAt: now,
                modelVersion: modelVersion
            )
        ]
    }

    func waitUntilCreateStarted() async {
        if isWaitingForRelease { return }
        await withCheckedContinuation { continuation in
            createStartedContinuation = continuation
        }
    }

    func releaseCreate() {
        createReleaseContinuation?.resume()
        createReleaseContinuation = nil
    }

    func fetchNotes(scanID: String) async throws -> [SpatialNote] {
        notes
    }

    func fetchNote(noteID: String) async throws -> SpatialNote {
        guard let note = notes.first(where: { $0.id == noteID }) else {
            throw NotesServiceError.noteNotFound
        }
        return note
    }

    func createNote(scanID: String, input: CreateNoteInput) async throws -> SpatialNote {
        isWaitingForRelease = true
        createStartedContinuation?.resume()
        createStartedContinuation = nil

        await withCheckedContinuation { continuation in
            createReleaseContinuation = continuation
        }

        let now = Date()
        let note = SpatialNote(
            id: UUID().uuidString,
            title: input.title,
            detail: input.description,
            color: input.color,
            position: input.position,
            orientation: input.orientation,
            createdAt: now,
            updatedAt: now,
            modelVersion: input.modelVersion
        )
        notes.append(note)
        return note
    }

    func updateNote(
        scanID: String,
        noteID: String,
        title: String,
        description: String,
        color: NoteColor
    ) async throws -> SpatialNote {
        throw NotesServiceError.noteNotFound
    }

    func moveNote(noteID: String, input: MoveNoteInput) async throws -> SpatialNote {
        throw NotesServiceError.noteNotFound
    }

    func deleteNote(scanID: String, noteID: String) async throws {
        throw NotesServiceError.noteNotFound
    }
}

@MainActor
private final class DelayedNotesService: NotesService {
    private let delayNanoseconds: UInt64
    private var notes: [SpatialNote] = []
    private(set) var moveCallCount = 0
    private let modelVersion = "sample-1"

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
        let now = Date()
        notes = [
            SpatialNote(
                id: "delayed-1",
                title: "Seed",
                detail: "Seed detail",
                color: .blue,
                position: .zero,
                orientation: .zero,
                createdAt: now,
                updatedAt: now,
                modelVersion: modelVersion
            )
        ]
    }

    func fetchNotes(scanID: String) async throws -> [SpatialNote] {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return notes
    }

    func fetchNote(noteID: String) async throws -> SpatialNote {
        guard let note = notes.first(where: { $0.id == noteID }) else {
            throw NotesServiceError.noteNotFound
        }
        return note
    }

    func createNote(scanID: String, input: CreateNoteInput) async throws -> SpatialNote {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        let now = Date()
        let note = SpatialNote(
            id: UUID().uuidString,
            title: input.title,
            detail: input.description,
            color: input.color,
            position: input.position,
            orientation: input.orientation,
            createdAt: now,
            updatedAt: now,
            modelVersion: input.modelVersion
        )
        notes.append(note)
        return note
    }

    func updateNote(
        scanID: String,
        noteID: String,
        title: String,
        description: String,
        color: NoteColor
    ) async throws -> SpatialNote {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else {
            throw NotesServiceError.noteNotFound
        }
        notes[index].title = title
        notes[index].detail = description
        notes[index].color = color
        return notes[index]
    }

    func moveNote(noteID: String, input: MoveNoteInput) async throws -> SpatialNote {
        moveCallCount += 1
        try await Task.sleep(nanoseconds: delayNanoseconds)
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else {
            throw NotesServiceError.noteNotFound
        }
        notes[index].position = input.position
        notes[index].orientation = input.orientation
        notes[index].modelVersion = input.modelVersion
        return notes[index]
    }

    func deleteNote(scanID: String, noteID: String) async throws {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        notes.removeAll { $0.id == noteID }
    }
}
