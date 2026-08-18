//
//  NoteEditorViewModelTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

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
