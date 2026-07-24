//
//  AuthenticationModelsTests.swift
//  roomscanTests
//

import Foundation
import Testing
@testable import roomscan

struct AuthenticationModelsTests {
    @Test func authenticationErrorDescriptionsAreNonEmpty() {
        let errors: [AuthenticationError] = [
            .cancelled,
            .appleSystemError,
            .invalidCredential,
            .networkError,
            .unavailable,
            .unknown
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    @Test func authenticationErrorEquality() {
        #expect(AuthenticationError.cancelled == AuthenticationError.cancelled)
        #expect(AuthenticationError.networkError == AuthenticationError.networkError)
        #expect(AuthenticationError.invalidCredential != AuthenticationError.appleSystemError)
    }

    @Test func authenticationProviderCases() {
        #expect(AuthenticationProvider.allCases.contains(.apple))
        #expect(AuthenticationProvider.allCases.contains(.google))
        #expect(AuthenticationProvider.allCases.contains(.facebook))
    }
}
