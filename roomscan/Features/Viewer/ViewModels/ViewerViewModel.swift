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

        var isFailed: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    let input: ViewerInput
    var scanTitle: String
    private let accessPolicy: DetailAccessPolicy
    private(set) var loadState: LoadState = .idle
    private(set) var modelSource: ModelSource?
    var notes: [SpatialNote] = []
    private(set) var isLoadingNotes = false
    var selectedNoteID: String?
    private(set) var viewMode: ViewerMode = .threeD
    private(set) var isFullscreen = false
    private(set) var areNotesVisible = true
    var placementMode: ViewerPlacementMode = .idle
    private(set) var cameraCommands: [PendingCameraCommand] = []
    var editorMode: NoteEditorMode?
    var notePendingDeletion: SpatialNote?
    var isBusy = false
    var operationErrorMessage: String?
    var placementDraftPosition: SIMD3<Float>?
    static let draftNoteID = "viewer-placement-draft"

    let notesService: any NotesService
    private let modelLoadingService: any ModelLoadingService
    let modelDownloadService: (any ScanDetailService)?
    var scanModelVersion: String?
    let noteDetailRequest = NoteDetailRequest()
    /// Note IDs whose detail has already been fetched in this viewer session.
    var fetchedNoteIDs: Set<String> = []

    init(
        input: ViewerInput,
        notesService: any NotesService,
        modelLoadingService: any ModelLoadingService,
        modelDownloadService: (any ScanDetailService)? = nil,
        accessPolicy: DetailAccessPolicy = .editable
    ) {
        self.input = input
        self.scanTitle = input.scanName
        self.accessPolicy = accessPolicy
        self.notesService = notesService
        self.modelLoadingService = modelLoadingService
        self.modelDownloadService = modelDownloadService
        self.scanModelVersion = input.modelVersion
    }

    convenience init(
        input: ViewerInput,
        notesService: any NotesService,
        accessPolicy: DetailAccessPolicy = .editable
    ) {
        self.init(
            input: input,
            notesService: notesService,
            modelLoadingService: DefaultModelLoadingService(),
            accessPolicy: accessPolicy
        )
    }

    func load() async {
        guard loadState == .idle || loadState.isFailed else { return }

        let isRetry = loadState.isFailed
        let startedAt = Date()
        modelSource = nil
        loadState = .loading
        do {
            let modelURL = try await resolveModelURL(forceDownload: isRetry)
            let source = try await modelLoadingService.resolveSource(modelURL: modelURL)
            modelSource = source
            if source == .sampleRoom {
                loadState = .loaded(source)
            }
        } catch is CancellationError {
            loadState = .idle
            return
        } catch let error as ModelLoadingError {
            modelSource = nil
            let didFinishRetryDelay = await keepRetryLoadingVisibleIfNeeded(
                isRetry: isRetry,
                startedAt: startedAt
            )
            guard didFinishRetryDelay, !Task.isCancelled else {
                loadState = .idle
                return
            }
            loadState = .failed(error)
            return
        } catch {
            modelSource = nil
            let didFinishRetryDelay = await keepRetryLoadingVisibleIfNeeded(
                isRetry: isRetry,
                startedAt: startedAt
            )
            guard didFinishRetryDelay, !Task.isCancelled else {
                loadState = .idle
                return
            }
            loadState = .failed(.loadFailed)
            return
        }
        isLoadingNotes = true
        defer { isLoadingNotes = false }
        do {
            notes = try await notesService.fetchNotes(scanID: input.scanID)
            resetNoteDetailCache()
        } catch is CancellationError {
            if case .loaded = loadState {
                return
            }
            loadState = .idle
            return
        } catch {
            notes = []
            operationErrorMessage = String(localized: "viewer.notes.load.error")
        }
    }

    func reportModelLoadFailed() {
        modelSource = nil
        loadState = .failed(.loadFailed)
    }

    func reportModelLoaded() {
        guard let modelSource else { return }
        loadState = .loaded(modelSource)
    }

    func retryLoad() {
        guard !isLoading else { return }
        Task {
            await load()
        }
    }
}

extension ViewerViewModel {
    var showsDeleteConfirmation: Bool { notePendingDeletion != nil }

    var showsOperationError: Bool { operationErrorMessage != nil }

    var isPlacementActive: Bool { placementMode != .idle }

    var allowsOwnerActions: Bool { accessPolicy.allowsOwnerActions }

    var showsNotesSection: Bool {
        allowsOwnerActions || isLoadingNotes || !notes.isEmpty
    }

    var canShare: Bool {
        RoomScanSummary.isReadyToShare(syncStatus: input.syncStatus, assetStatus: input.assetStatus)
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
        switch placementMode {
        case .idle:
            return areNotesVisible ? notes : []
        case .placingNew:
            let savedNotes = areNotesVisible ? notes : []
            guard let placementDraftPosition else { return savedNotes }
            let draftNote = SpatialNote(
                id: Self.draftNoteID,
                title: String(localized: "viewer.note.draft.title"),
                detail: "",
                color: .default,
                position: placementDraftPosition,
                orientation: .zero,
                createdAt: .now,
                updatedAt: .now,
                modelVersion: "draft"
            )
            return savedNotes + [draftNote]
        case .moving:
            guard let movingNote else {
                return areNotesVisible ? notes : []
            }
            guard let placementDraftPosition else {
                return areNotesVisible ? notes : [movingNote]
            }
            var relocated = movingNote
            relocated.position = placementDraftPosition
            if areNotesVisible {
                return notes.map { note in
                    note.id == movingNote.id ? relocated : note
                }
            }
            return [relocated]
        }
    }

    var shareLink: URL {
        let base = URL(string: "https://roomscan.app/scans")!
        return base.appending(path: input.scanID)
    }

    func toggleNotesVisibility() {
        areNotesVisible.toggle()
        if !areNotesVisible {
            selectedNoteID = nil
        }
    }

    func zoomIn() {
        enqueueCameraCommand(.zoomIn)
    }

    func zoomOut() {
        enqueueCameraCommand(.zoomOut)
    }

    func resetCamera() {
        enqueueCameraCommand(.reset)
    }

    func consumeCameraCommands(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        cameraCommands.removeAll { ids.contains($0.id) }
    }

    func enqueueCameraCommand(_ command: CameraCommand) {
        cameraCommands.append(PendingCameraCommand(command))
    }

    func beginAddNote() {
        guard allowsOwnerActions, !isBusy else { return }
        placementMode = .placingNew
        placementDraftPosition = nil
        selectedNoteID = nil
    }

    func beginMoveNote(_ note: SpatialNote) {
        guard allowsOwnerActions, !isBusy else { return }
        placementMode = .moving(noteID: note.id)
        selectedNoteID = note.id
        placementDraftPosition = note.position
    }

    func cancelPlacement() {
        guard !isBusy else { return }
        placementMode = .idle
        placementDraftPosition = nil
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
        guard allowsOwnerActions else { return }
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

    func reportOperationError(_ message: String) {
        operationErrorMessage = message
    }

    func openEditor(for note: SpatialNote) {
        guard allowsOwnerActions else { return }
        Task {
            await openEditor(noteID: note.id)
        }
    }

    func requestDelete(_ note: SpatialNote) {
        guard allowsOwnerActions else { return }
        notePendingDeletion = note
    }

    func cancelDelete() {
        notePendingDeletion = nil
    }

    func setViewMode(_ mode: ViewerMode) {
        // Same-mode taps must not assign `viewMode`: @Observable notifies on every
        // write, which re-renders the canvas. Re-centering the current mode is
        // `resetCamera()` (toolbar), not re-selecting the chip — and
        // `RoomModelCanvas` already skips `applyViewMode` when the mode is unchanged.
        guard mode != viewMode else { return }
        viewMode = mode
    }

    func toggleFullscreen() {
        isFullscreen.toggle()
    }
}
