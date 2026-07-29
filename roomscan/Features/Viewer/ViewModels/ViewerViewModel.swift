//
//  ViewerViewModel.swift
//  roomscan
//

import Foundation
import Observation
import simd

@MainActor
@Observable
final class ViewerViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(ModelSource)
        case failed(ModelLoadingError)
    }

    let input: ViewerInput

    private(set) var scanTitle: String
    private(set) var loadState: LoadState = .idle
    private(set) var notes: [SpatialNote] = []
    private(set) var selectedNoteID: String?
    private(set) var viewMode: ViewerMode = .threeD
    private(set) var isFullscreen = false
    private(set) var areNotesVisible = true
    private(set) var placementMode: ViewerPlacementMode = .idle
    private(set) var cameraCommand: CameraCommand?
    private(set) var editorMode: NoteEditorMode?
    private(set) var notePendingDeletion: SpatialNote?
    private(set) var isBusy = false
    private(set) var operationErrorMessage: String?
    private(set) var placementDraftPosition: SIMD3<Float>?

    private static let draftNoteID = "viewer-placement-draft"

    var showsDeleteConfirmation: Bool {
        notePendingDeletion != nil
    }

    var showsOperationError: Bool {
        operationErrorMessage != nil
    }

    var isPlacementActive: Bool {
        placementMode != .idle
    }

    var movingNote: SpatialNote? {
        guard case .moving(let noteID) = placementMode else { return nil }
        return notes.first(where: { $0.id == noteID })
    }

    var draggableNoteID: String? {
        switch placementMode {
        case .idle:
            return nil
        case .placingNew:
            return placementDraftPosition == nil ? nil : Self.draftNoteID
        case .moving(let noteID):
            return noteID
        }
    }

    var isLoading: Bool {
        if case .loading = loadState { return true }
        return false
    }

    var isModelReady: Bool {
        if case .loaded = loadState { return true }
        return false
    }

    var visibleNotes: [SpatialNote] {
        guard areNotesVisible else { return [] }
        switch placementMode {
        case .idle:
            return notes
        case .placingNew:
            guard let placementDraftPosition else { return notes }
            let draftNote = SpatialNote(
                id: Self.draftNoteID,
                title: String(localized: "viewer.note.draft.title"),
                detail: "",
                color: .default,
                position: placementDraftPosition,
                createdAt: .now,
                updatedAt: .now,
                modelVersion: "draft"
            )
            return notes + [draftNote]
        case .moving:
            guard let movingNote, let placementDraftPosition else { return notes }
            return notes.map { note in
                guard note.id == movingNote.id else { return note }
                var updated = note
                updated.position = placementDraftPosition
                return updated
            }
        }
    }

    var shareLink: URL {
        let base = URL(string: "https://roomscan.app/scans")!
        return base.appending(path: input.scanID)
    }

    private let notesService: any NotesService
    private let modelLoadingService: any ModelLoadingService

    init(
        input: ViewerInput,
        notesService: any NotesService,
        modelLoadingService: any ModelLoadingService
    ) {
        self.input = input
        self.scanTitle = input.scanName
        self.notesService = notesService
        self.modelLoadingService = modelLoadingService
    }

    convenience init(
        input: ViewerInput,
        notesService: any NotesService
    ) {
        self.init(
            input: input,
            notesService: notesService,
            modelLoadingService: DefaultModelLoadingService()
        )
    }

    func load() async {
        guard loadState == .idle || loadState.isFailed else { return }

        loadState = .loading
        do {
            let source = try await modelLoadingService.resolveSource(modelURL: input.modelURL)
            notes = try await notesService.fetchNotes(scanID: input.scanID)
            loadState = .loaded(source)
        } catch let error as ModelLoadingError {
            loadState = .failed(error)
        } catch {
            loadState = .failed(.loadFailed)
        }
    }

    func reportModelLoadFailed() {
        loadState = .failed(.loadFailed)
    }

    func retryLoad() {
        guard !isLoading else { return }
        Task {
            await load()
        }
    }

    func setViewMode(_ mode: ViewerMode) {
        viewMode = mode
    }

    func toggleFullscreen() {
        isFullscreen.toggle()
    }

    func renameScan(to title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        scanTitle = trimmedTitle
    }

    func toggleNotesVisibility() {
        areNotesVisible.toggle()
        if !areNotesVisible {
            selectedNoteID = nil
        }
    }

    func zoomIn() {
        cameraCommand = .zoomIn
    }

    func zoomOut() {
        cameraCommand = .zoomOut
    }

    func resetCamera() {
        cameraCommand = .reset
    }

    func consumeCameraCommand() {
        cameraCommand = nil
    }

    func beginAddNote() {
        guard !isBusy else { return }
        placementMode = .placingNew
        placementDraftPosition = nil
        selectedNoteID = nil
    }

    func beginMoveNote(_ note: SpatialNote) {
        guard !isBusy else { return }
        placementMode = .moving(noteID: note.id)
        selectedNoteID = note.id
        placementDraftPosition = note.position
    }

    func cancelPlacement() {
        guard !isBusy else { return }
        placementMode = .idle
        placementDraftPosition = nil
    }

    func selectNote(id: String?) {
        selectedNoteID = id
        guard let id, let note = notes.first(where: { $0.id == id }) else { return }
        cameraCommand = .focus(note.position)
    }

    func handleCanvasTap(position: SIMD3<Float>) {
        switch placementMode {
        case .idle:
            break
        case .placingNew:
            placementDraftPosition = position
        case .moving(let noteID):
            selectedNoteID = noteID
        }
    }

    func updateMoveDraft(position: SIMD3<Float>) {
        guard placementDraftPosition != nil else { return }
        placementDraftPosition = position
    }

    func confirmPlacement() {
        switch placementMode {
        case .idle:
            return
        case .placingNew:
            guard let placementDraftPosition else { return }
            editorMode = .create(position: placementDraftPosition)
            placementMode = .idle
            self.placementDraftPosition = nil
        case .moving(let noteID):
            guard let placementDraftPosition, !isBusy else { return }
            isBusy = true
            Task {
                await moveNote(noteID: noteID, to: placementDraftPosition)
            }
        }
    }

    func handlePinTap(noteID: String) {
        guard placementMode == .idle else { return }
        selectNote(id: noteID)
    }

    func dismissEditor() {
        editorMode = nil
    }

    func dismissOperationError() {
        operationErrorMessage = nil
    }

    func saveEditor(title: String, description: String, color: NoteColor) async -> Bool {
        guard let editorMode, !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }

        do {
            switch editorMode {
            case .create(let position):
                let note = try await notesService.createNote(
                    scanID: input.scanID,
                    title: title,
                    description: description,
                    color: color,
                    position: position
                )
                notes.append(note)
                selectedNoteID = note.id
                cameraCommand = .focus(note.position)
            case .edit(let existing):
                let updated = try await notesService.updateNote(
                    scanID: input.scanID,
                    noteID: existing.id,
                    title: title,
                    description: description,
                    color: color
                )
                if let index = notes.firstIndex(where: { $0.id == updated.id }) {
                    notes[index] = updated
                }
                selectedNoteID = updated.id
            }
            self.editorMode = nil
            return true
        } catch {
            return false
        }
    }

    func openEditor(for note: SpatialNote) {
        editorMode = .edit(note)
    }

    func requestDelete(_ note: SpatialNote) {
        notePendingDeletion = note
    }

    func cancelDelete() {
        notePendingDeletion = nil
    }

    func confirmDelete(_ note: SpatialNote) async {
        guard !isBusy else {
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            try await notesService.deleteNote(scanID: input.scanID, noteID: note.id)
            notes.removeAll { $0.id == note.id }

            if selectedNoteID == note.id {
                selectedNoteID = nil
            }

            notePendingDeletion = nil
        } catch {
            operationErrorMessage = String(localized: "viewer.note.delete.error")
            notePendingDeletion = nil
        }
    }

    /// Assumes `isBusy` was set by the caller before the Task started.
    private func moveNote(noteID: String, to position: SIMD3<Float>) async {
        defer {
            isBusy = false
            placementMode = .idle
            placementDraftPosition = nil
        }

        do {
            let updated = try await notesService.moveNote(
                scanID: input.scanID,
                noteID: noteID,
                position: position
            )
            if let index = notes.firstIndex(where: { $0.id == updated.id }) {
                notes[index] = updated
            }
            selectedNoteID = updated.id
            cameraCommand = .focus(updated.position)
        } catch {
            operationErrorMessage = String(localized: "viewer.note.move.error")
        }
    }
}

private extension ViewerViewModel.LoadState {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
