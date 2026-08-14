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
    private let accessPolicy: DetailAccessPolicy
    private(set) var loadState: LoadState = .idle
    private(set) var modelSource: ModelSource?
    private(set) var notes: [SpatialNote] = []
    private(set) var isLoadingNotes = false
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

    var allowsOwnerActions: Bool {
        accessPolicy.allowsOwnerActions
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
                orientation: .zero,
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
    private let modelDownloadService: (any ScanDetailService)?
    private var scanModelVersion: String?

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
        } catch let error as ModelLoadingError {
            modelSource = nil
            await keepRetryLoadingVisibleIfNeeded(isRetry: isRetry, startedAt: startedAt)
            loadState = .failed(error)
            return
        } catch {
            modelSource = nil
            await keepRetryLoadingVisibleIfNeeded(isRetry: isRetry, startedAt: startedAt)
            loadState = .failed(.loadFailed)
            return
        }

        isLoadingNotes = true
        defer { isLoadingNotes = false }
        do {
            notes = try await notesService.fetchNotes(scanID: input.scanID)
        } catch {
            notes = []
            operationErrorMessage = String(localized: "viewer.notes.load.error")
        }
    }

    private func keepRetryLoadingVisibleIfNeeded(isRetry: Bool, startedAt: Date) async {
        guard isRetry else { return }
        let remainingDuration = 3 - Date().timeIntervalSince(startedAt)
        guard remainingDuration > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(remainingDuration * 1_000_000_000))
    }

    private func resolveModelURL(forceDownload: Bool) async throws -> URL? {
        let destinationURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("Scans", isDirectory: true)
        .appendingPathComponent(input.scanID, isDirectory: true)
        .appendingPathComponent("mesh.usdz")

        if !forceDownload || modelDownloadService == nil {
            if let modelURL = input.modelURL,
               FileManager.default.fileExists(atPath: modelURL.path) {
                return modelURL
            }

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                return destinationURL
            }
        }

        guard let modelDownloadService else { return input.modelURL }
        try await modelDownloadService.downloadModel(scanID: input.scanID, to: destinationURL)
        return destinationURL
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

    func selectNote(id: String?) {
        selectedNoteID = id
        guard let id else { return }

        if let note = notes.first(where: { $0.id == id }) {
            cameraCommand = .focus(note.position)
        }

        Task {
            await refreshNoteDetail(noteID: id)
        }
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
}

extension ViewerViewModel {
    func setViewMode(_ mode: ViewerMode) {
        viewMode = mode
    }

    func toggleFullscreen() {
        isFullscreen.toggle()
    }

    func renameScan(to title: String) -> Bool {
        guard allowsOwnerActions else { return false }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }
        scanTitle = trimmedTitle
        return true
    }

    func saveEditor(title: String, description: String, color: NoteColor) async -> Bool {
        guard allowsOwnerActions else {
            logNote("save skipped reason=owner-actions-not-allowed scanID=\(input.scanID)")
            return false
        }
        guard let editorMode else {
            logNote("save skipped reason=editor-not-present scanID=\(input.scanID)")
            return false
        }
        guard !isBusy else {
            logNote("save skipped reason=operation-in-progress scanID=\(input.scanID)")
            return false
        }
        isBusy = true
        defer { isBusy = false }
        do {
            switch editorMode {
            case .create(let position):
                guard try await saveNewNote(
                    title: title,
                    description: description,
                    color: color,
                    position: position
                ) else {
                    operationErrorMessage = String(localized: "viewer.note.save.error")
                    return false
                }
            case .edit(let existing):
                try await saveExistingNote(
                    existing,
                    title: title,
                    description: description,
                    color: color
                )
            }
            self.editorMode = nil
            return true
        } catch {
            logNote("save failed scanID=\(input.scanID) category=operation")
            operationErrorMessage = String(localized: "viewer.note.save.error")
            return false
        }
    }
    private func saveNewNote(
        title: String,
        description: String,
        color: NoteColor,
        position: SIMD3<Float>
    ) async throws -> Bool {
        guard let modelVersion = await resolveModelVersion() else {
            logNote("create skipped reason=model-version-unavailable scanID=\(input.scanID)")
            return false
        }
        logNote("create started scanID=\(input.scanID) modelVersion=\(modelVersion)")
        let note = try await notesService.createNote(
            scanID: input.scanID,
            input: CreateNoteInput(
                title: title,
                description: description,
                color: color,
                position: position,
                orientation: .zero,
                modelVersion: modelVersion
            )
        )
        notes.append(note)
        selectedNoteID = note.id
        cameraCommand = .focus(note.position)
        logNote("create succeeded scanID=\(input.scanID) noteID=\(note.id)")
        return true
    }

    private func saveExistingNote(
        _ existing: SpatialNote,
        title: String,
        description: String,
        color: NoteColor
    ) async throws {
        logNote("update started scanID=\(input.scanID) noteID=\(existing.id)")
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
        logNote("update succeeded scanID=\(input.scanID) noteID=\(updated.id)")
    }

    func confirmDelete(_ note: SpatialNote) async {
        guard allowsOwnerActions else { return }
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
            guard let existing = notes.first(where: { $0.id == noteID }) else {
                operationErrorMessage = String(localized: "viewer.note.move.error")
                return
            }
            let updated = try await notesService.moveNote(
                noteID: noteID,
                input: MoveNoteInput(
                    position: position,
                    orientation: existing.orientation,
                    modelVersion: existing.modelVersion
                )
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

    func refreshNoteDetail(noteID: String) async {
        do {
            let note = try await notesService.fetchNote(noteID: noteID)
            applyFetchedNote(note)
        } catch {}
    }

    func openEditor(noteID: String) async {
        guard allowsOwnerActions, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let note = try await notesService.fetchNote(noteID: noteID)
            applyFetchedNote(note)
            editorMode = .edit(note)
            selectedNoteID = noteID
        } catch {
            operationErrorMessage = String(localized: "viewer.notes.load.error")
        }
    }

    func applyFetchedNote(_ note: SpatialNote) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        }
        if selectedNoteID == note.id {
            cameraCommand = .focus(note.position)
        }
    }

    /// The scan detail is authoritative; local note metadata is only used offline.
    private func resolveModelVersion() async -> String? {
        if let scanModelVersion, !scanModelVersion.isEmpty {
            return scanModelVersion
        }

        if let modelDownloadService {
            do {
                let detail = try await modelDownloadService.fetchScanDetail(id: input.scanID)
                let modelVersion = String(detail.modelVersion)
                scanModelVersion = modelVersion
                logNote("model version loaded scanID=\(input.scanID) modelVersion=\(modelVersion)")
                return modelVersion
            } catch {
                logNote(
                    "model version unavailable scanID=\(input.scanID) " +
                    "category=\(modelVersionLoadFailureCategory(error))"
                )
                return nil
            }
        }

        return notes.first(where: { !$0.modelVersion.isEmpty })?.modelVersion
    }

    private func modelVersionLoadFailureCategory(_ error: Error) -> String {
        guard let error = error as? HTTPClientError else { return "unexpected" }
        if case .serverError(let statusCode, _) = error { return "server-\(statusCode)" }
        if case .networkError = error { return "network" }
        if case .invalidURL = error { return "invalid-url" }
        return "decoding"
    }

    private func logNote(_ message: String) {
        #if DEBUG
        print("[Notes] \(message)")
        #endif
    }
}

private extension ViewerViewModel.LoadState {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
