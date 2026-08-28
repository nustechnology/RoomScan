//
//  AppleUserDisplayNameTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

struct AppleUserDisplayNameTests {
    @Test func formattedReturnsNilForMissingOrBlankComponents() {
        #expect(AppleUserDisplayName.formatted(from: nil) == nil)

        let blank = PersonNameComponents()
        #expect(AppleUserDisplayName.formatted(from: blank) == nil)
    }

    @Test func resolvedPrefersAppleFullNameOverAPIDisplayName() {
        var appleName = PersonNameComponents()
        appleName.givenName = "Jane"
        appleName.familyName = "Doe"

        let formatted = AppleUserDisplayName.formatted(from: appleName)

        #expect(formatted != nil)
        #expect(
            AppleUserDisplayName.resolved(
                appleFullName: appleName,
                apiDisplayName: "API Name"
            ) == formatted
        )
    }

    @Test func resolvedFallsBackToAPIDisplayName() {
        #expect(
            AppleUserDisplayName.resolved(
                appleFullName: nil,
                apiDisplayName: "  Ada  "
            ) == "Ada"
        )
        #expect(
            AppleUserDisplayName.resolved(
                appleFullName: PersonNameComponents(),
                apiDisplayName: "Ada"
            ) == "Ada"
        )
    }

    @Test func resolvedReturnsNilWhenBothSourcesAreBlank() {
        #expect(
            AppleUserDisplayName.resolved(
                appleFullName: nil,
                apiDisplayName: "   "
            ) == nil
        )
    }

    @Test func nameToUploadToAPIOnlyWhenAppleNameExistsAndAPIIsBlank() {
        var appleName = PersonNameComponents()
        appleName.givenName = "Jane"
        appleName.familyName = "Doe"
        let formatted = AppleUserDisplayName.formatted(from: appleName)

        #expect(
            AppleUserDisplayName.nameToUploadToAPI(
                appleFullName: appleName,
                apiDisplayName: nil
            ) == formatted
        )
        #expect(
            AppleUserDisplayName.nameToUploadToAPI(
                appleFullName: appleName,
                apiDisplayName: "  "
            ) == formatted
        )
        #expect(
            AppleUserDisplayName.nameToUploadToAPI(
                appleFullName: appleName,
                apiDisplayName: "Existing"
            ) == nil
        )
        #expect(
            AppleUserDisplayName.nameToUploadToAPI(
                appleFullName: nil,
                apiDisplayName: nil
            ) == nil
        )
    }
}
