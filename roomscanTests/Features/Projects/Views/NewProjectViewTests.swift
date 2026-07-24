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
}
