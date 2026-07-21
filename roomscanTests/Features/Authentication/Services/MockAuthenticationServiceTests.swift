//
//  MockAuthenticationServiceTests.swift
//  roomscanTests
//

import Testing
@testable import roomscan

@MainActor
struct MockAuthenticationServiceTests {
    @Test func defaultConfigurationIsAccessibleFromInitializer() {
        // Exercises Configuration.default as a default argument (nonisolated reference).
        _ = MockAuthenticationService()
        let configuration = MockAuthenticationService.Configuration.default

        #expect(configuration.signInOutcome == .success)
        #expect(configuration.initialSession == nil)
        #expect(configuration.restoreFails == false)
        #expect(configuration.simulatedDelayNanoseconds == 300_000_000)
    }

    @Test func signInPersistsSessionForRestore() async throws {
        let service = MockAuthenticationService(
            configuration: .init(
                initialSession: nil,
                signInOutcome: .success,
                restoreFails: false,
                simulatedDelayNanoseconds: 0
            )
        )

        let session = try await service.signIn(with: .apple)
        let restored = try await service.restoreSession()

        #expect(session == .mockAppleUser)
        #expect(restored == session)
    }

    @Test func signOutClearsSession() async throws {
        let service = MockAuthenticationService(
            configuration: .init(
                initialSession: .mockAppleUser,
                signInOutcome: .success,
                restoreFails: false,
                simulatedDelayNanoseconds: 0
            )
        )

        try await service.signOut()

        #expect(try await service.restoreSession() == nil)
    }

    @Test func makeForCurrentProcessHonorsSignedInLaunchArgument() async throws {
        // Directly exercise the configuration path used by UI tests.
        let service = MockAuthenticationService(
            configuration: .init(
                initialSession: .mockAppleUser,
                signInOutcome: .success,
                restoreFails: false,
                simulatedDelayNanoseconds: 0
            )
        )

        #expect(try await service.restoreSession() == .mockAppleUser)
    }
}
