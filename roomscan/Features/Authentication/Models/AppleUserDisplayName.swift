//
//  AppleUserDisplayName.swift
//  roomscan
//

import Foundation

enum AppleUserDisplayName {
    static func formatted(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .default
        let name = formatter.string(from: components).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    static func resolved(appleFullName: PersonNameComponents?, apiDisplayName: String?) -> String? {
        formatted(from: appleFullName) ?? nonBlank(apiDisplayName)
    }

    /// Apple sends `fullName` only on the first authorization. Upload that value when the API
    /// has no display name so later sign-ins can resolve it from the backend.
    static func nameToUploadToAPI(
        appleFullName: PersonNameComponents?,
        apiDisplayName: String?
    ) -> String? {
        guard let appleName = formatted(from: appleFullName) else { return nil }
        guard nonBlank(apiDisplayName) == nil else { return nil }
        return appleName
    }

    static func nonBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
