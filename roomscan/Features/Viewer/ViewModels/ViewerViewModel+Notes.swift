//
//  ViewerViewModel+Notes.swift
//  roomscan
//

import Foundation
import simd

extension ViewerViewModel {
    func selectNote(id: String?) {
        selectedNoteID = id
        guard let id else {
            noteDetailRequest.cancel()
            return
        }

        if let note = notes.first(where: { $0.id == id }) {
            enqueueCameraCommand(.focus(note.position))
        }

        guard !fetchedNoteIDs.contains(id) else { return }
        guard noteDetailRequest.noteID != id else { return }

        startNoteDetailFetch(noteID: id)
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
            invalidateFetchedNote(id: note.id)

            if selectedNoteID == note.id {
                selectedNoteID = nil
            }

            notePendingDeletion = nil
        } catch {
            operationErrorMessage = String(localized: "viewer.note.delete.error")
            notePendingDeletion = nil
        }
    }

    func openEditor(noteID: String) async {
        guard allowsOwnerActions, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let note: SpatialNote
            if fetchedNoteIDs.contains(noteID),
               let cached = notes.first(where: { $0.id == noteID }) {
                note = cached
            } else {
                note = try await notesService.fetchNote(noteID: noteID)
                applyFetchedNote(note)
                fetchedNoteIDs.insert(noteID)
            }
            editorMode = .edit(note)
            selectedNoteID = noteID
        } catch {
            operationErrorMessage = String(localized: "viewer.notes.load.error")
        }
    }

    func applyFetchedNote(_ note: SpatialNote) {
        let cachedPosition = notes.first(where: { $0.id == note.id })?.position
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        }
        if selectedNoteID == note.id, cachedPosition != note.position {
            enqueueCameraCommand(.focus(note.position))
        }
    }

    func resetNoteDetailCache() {
        fetchedNoteIDs.removeAll()
        noteDetailRequest.cancel()
    }

    /// Assumes `isBusy` was set by the caller before the Task started.
    func moveNote(noteID: String, to position: SIMD3<Float>) async {
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
            invalidateFetchedNote(id: noteID)
            selectedNoteID = updated.id
            enqueueCameraCommand(.focus(updated.position))
        } catch {
            operationErrorMessage = String(localized: "viewer.note.move.error")
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
        // Leave unfetched so the next select refreshes detail from the API.
        invalidateFetchedNote(id: note.id)
        selectedNoteID = note.id
        enqueueCameraCommand(.focus(note.position))
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
        invalidateFetchedNote(id: updated.id)
        selectedNoteID = updated.id
        logNote("update succeeded scanID=\(input.scanID) noteID=\(updated.id)")
    }

    private func startNoteDetailFetch(noteID: String) {
        let generation = noteDetailRequest.start(noteID: noteID)
        let notesService = notesService
        noteDetailRequest.task = Task { [weak self, notesService] in
            do {
                let note = try await notesService.fetchNote(noteID: noteID)
                guard let self else { return }
                guard self.noteDetailRequest.generation == generation else { return }
                self.applyFetchedNote(note)
                self.fetchedNoteIDs.insert(noteID)
                self.noteDetailRequest.finish(generation: generation)
            } catch is CancellationError {
                self?.noteDetailRequest.finish(generation: generation)
            } catch {
                guard let self else { return }
                self.logNote("detail fetch failed noteID=\(noteID)")
                self.noteDetailRequest.finish(generation: generation)
            }
        }
    }

    private func invalidateFetchedNote(id: String) {
        fetchedNoteIDs.remove(id)
        if noteDetailRequest.noteID == id {
            noteDetailRequest.cancel()
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
