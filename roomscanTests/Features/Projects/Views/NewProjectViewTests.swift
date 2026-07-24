//
//  NewProjectViewTests.swift
//  roomscanTests
//

import Testing
@testable import roomscan

struct NewProjectViewTests {
    @Test func projectNameRequiresNonWhitespaceCharacters() {
        #expect(!ProjectValidation.isValidName("   "))
        #expect(ProjectValidation.isValidName("Căn hộ của tôi"))
    }

    @Test func projectNameMustBeAtMostFiftyCharacters() {
        #expect(ProjectValidation.isValidName(String(repeating: "a", count: 50)))
        #expect(!ProjectValidation.isValidName(String(repeating: "a", count: 51)))
    }

    @Test func projectDescriptionMustBeAtMostFiveHundredCharacters() {
        #expect(ProjectValidation.isValidDescription(String(repeating: "a", count: 500)))
        #expect(!ProjectValidation.isValidDescription(String(repeating: "a", count: 501)))
    }

    @Test func createModeIsDirtyWhenAnyFieldHasContent() {
        #expect(
            ProjectValidation.isDirty(
                name: "A",
                description: "",
                originalName: "",
                originalDescription: "",
                mode: .create
            )
        )
        #expect(
            !ProjectValidation.isDirty(
                name: "",
                description: "",
                originalName: "",
                originalDescription: "",
                mode: .create
            )
        )
    }

    @Test func editModeIsDirtyOnlyWhenValuesChangeFromOriginals() {
        #expect(
            !ProjectValidation.isDirty(
                name: "Lakeside",
                description: "Kitchen",
                originalName: "Lakeside",
                originalDescription: "Kitchen",
                mode: .edit
            )
        )
        #expect(
            ProjectValidation.isDirty(
                name: "Lakeside Remodel",
                description: "Kitchen",
                originalName: "Lakeside",
                originalDescription: "Kitchen",
                mode: .edit
            )
        )
        #expect(
            ProjectValidation.isDirty(
                name: "Lakeside",
                description: "Updated",
                originalName: "Lakeside",
                originalDescription: "Kitchen",
                mode: .edit
            )
        )
    }

    @Test func editModeCanSaveRequiresValidNameAndDirtyFields() {
        #expect(
            !ProjectValidation.canSave(
                name: "Lakeside",
                description: "Kitchen",
                originalName: "Lakeside",
                originalDescription: "Kitchen",
                mode: .edit
            )
        )
        #expect(
            !ProjectValidation.canSave(
                name: "   ",
                description: "Kitchen",
                originalName: "Lakeside",
                originalDescription: "Kitchen",
                mode: .edit
            )
        )
        #expect(
            ProjectValidation.canSave(
                name: "Updated Name",
                description: "Kitchen",
                originalName: "Lakeside",
                originalDescription: "Kitchen",
                mode: .edit
            )
        )
    }
}
