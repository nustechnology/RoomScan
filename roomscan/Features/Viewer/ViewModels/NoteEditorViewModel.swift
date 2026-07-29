//
//  NoteEditorViewModel.swift
//  roomscan
//

import Foundation
import Observation

@MainActor
@Observable
final class NoteEditorViewModel {
    static let titleLimit = NoteContentLimits.title
    static let descriptionLimit = NoteContentLimits.description

    private(set) var mode: NoteEditorMode
    var title: String
    var noteDescription: String
    var color: NoteColor
    private(set) var isSaving = false
    private(set) var validationMessage: String?

    init(mode: NoteEditorMode) {
        self.mode = mode
        switch mode {
        case .create:
            title = ""
            noteDescription = ""
            color = .default
        case .edit(let note):
            title = note.title
            noteDescription = note.detail
            color = note.color
        }
    }

    var titleCharacterCount: Int { title.count }
    var descriptionCharacterCount: Int { noteDescription.count }

    var canSave: Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = noteDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedTitle.isEmpty
            && !trimmedDescription.isEmpty
            && trimmedTitle.count <= Self.titleLimit
            && trimmedDescription.count <= Self.descriptionLimit
            && !isSaving
    }

    func updateTitle(_ value: String) {
        title = String(value.prefix(Self.titleLimit))
        validationMessage = nil
    }

    func updateDescription(_ value: String) {
        noteDescription = String(value.prefix(Self.descriptionLimit))
        validationMessage = nil
    }

    func selectColor(_ value: NoteColor) {
        color = value
    }

    func setSaving(_ value: Bool) {
        isSaving = value
    }

    func reportSaveFailed() {
        validationMessage = String(localized: "viewer.note.save.error")
    }

    func validatedTitle() -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            validationMessage = String(localized: "viewer.note.validation.titleRequired")
            return nil
        }
        return trimmed
    }

    func validatedDescription() -> String? {
        let trimmed = noteDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            validationMessage = String(localized: "viewer.note.validation.descriptionRequired")
            return nil
        }
        return trimmed
    }
}
