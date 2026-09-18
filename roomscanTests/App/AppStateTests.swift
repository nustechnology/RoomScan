//
//  AppStateTests.swift
//  roomscanTests
//

import Testing
@testable import roomscan

@MainActor
struct AppStateTests {
    @Test func restoreSessionSignsOutWhenNoSessionExists() async {
        let service = MockAuthenticationService(
            configuration: .init(
                initialSession: nil,
                signInOutcome: .success,
                restoreFails: false,
                simulatedDelayNanoseconds: 0
            )
        )
        let appState = AppState(authenticationService: service)

        await appState.restoreSession()

        #expect(appState.phase == .signedOut)
        #expect(appState.isAuthenticated == false)
    }

    @Test func restoreSessionAuthenticatesWhenSessionExists() async {
        let service = MockAuthenticationService(
            configuration: .init(
                initialSession: .mockAppleUser,
                signInOutcome: .success,
                restoreFails: false,
                simulatedDelayNanoseconds: 0
            )
        )
        let appState = AppState(authenticationService: service)

        await appState.restoreSession()

        #expect(appState.phase == .authenticated(.mockAppleUser))
        #expect(appState.currentSession == .mockAppleUser)
    }

    @Test func restoreSessionSurfacesRecoverableFailure() async {
        let service = MockAuthenticationService(
            configuration: .init(
                initialSession: nil,
                signInOutcome: .success,
                restoreFails: true,
                simulatedDelayNanoseconds: 0
            )
        )
        let appState = AppState(authenticationService: service)

        await appState.restoreSession()

        #expect(appState.phase == .restoreFailed(.unavailable))
    }

    @Test func applySignedInSessionUpdatesPhase() {
        let service = MockAuthenticationService(
            configuration: .init(
                initialSession: nil,
                signInOutcome: .success,
                restoreFails: false,
                simulatedDelayNanoseconds: 0
            )
        )
        let appState = AppState(authenticationService: service)

        appState.applySignedInSession(.mockAppleUser)

        #expect(appState.phase == .authenticated(.mockAppleUser))
    }

    @Test func updateSignedInUserPersistsNewPublicUserIdForRestore() async {
        let legacySession = AuthenticationSession(
            user: AuthenticatedUser(id: "u1", displayName: "Jane", email: "jane@example.com"),
            provider: .apple
        )
        let service = MockAuthenticationService(
            configuration: .init(
                initialSession: legacySession,
                signInOutcome: .success,
                restoreFails: false,
                simulatedDelayNanoseconds: 0
            )
        )
        let appState = AppState(authenticationService: service)
        await appState.restoreSession()

        await appState.updateSignedInUser(
            AuthenticatedUser(id: "u1", displayName: "Jane", email: "jane@example.com", publicUserId: "JANE123456")
        )

        let restored = try? await service.restoreSession()
        #expect(appState.currentSession?.user.publicUserId == "JANE123456")
        #expect(appState.currentSession?.provider == .apple)
        #expect(restored?.user.publicUserId == "JANE123456")
    }

    @Test func updateSignedInUserDoesNotSignBackInAfterSignOut() async {
        let service = MockAuthenticationService(
            configuration: .init(
                initialSession: nil,
                signInOutcome: .success,
                restoreFails: false,
                simulatedDelayNanoseconds: 0
            )
        )
        let appState = AppState(authenticationService: service)
        await appState.restoreSession()

        await appState.updateSignedInUser(AuthenticationSession.mockAppleUser.user)

        #expect(appState.phase == .signedOut)
    }

    @Test func updateSignedInUserIgnoresProfileFromAnotherAccount() async {
        let service = MockAuthenticationService(
            configuration: .init(
                initialSession: .mockAppleUser,
                signInOutcome: .success,
                restoreFails: false,
                simulatedDelayNanoseconds: 0
            )
        )
        let appState = AppState(authenticationService: service)
        await appState.restoreSession()

        await appState.updateSignedInUser(
            AuthenticatedUser(id: "previous-account", displayName: "Previous", email: nil, publicUserId: "PREV123456")
        )

        let restored = try? await service.restoreSession()
        #expect(appState.currentSession == .mockAppleUser)
        #expect(restored?.user.publicUserId == AuthenticationSession.mockAppleUser.user.publicUserId)
    }

    @Test func mockProfileRefreshAppliesToMockSignedInAccount() async throws {
        let service = MockAuthenticationService(
            configuration: .init(
                initialSession: .mockAppleUser,
                signInOutcome: .success,
                restoreFails: false,
                simulatedDelayNanoseconds: 0
            )
        )
        let appState = AppState(authenticationService: service)
        await appState.restoreSession()
        let session = try #require(appState.currentSession)

        let renamed = try await MockUsersService.makeForCurrentProcess().updateMe(
            displayName: "Renamed",
            fallingBackTo: session.user
        )
        await appState.updateSignedInUser(renamed)

        #expect(appState.currentSession?.user.displayName == "Renamed")
    }

    @Test func signOutReturnsToSignedOut() async {
        let service = MockAuthenticationService(
            configuration: .init(
                initialSession: .mockAppleUser,
                signInOutcome: .success,
                restoreFails: false,
                simulatedDelayNanoseconds: 0
            )
        )
        let appState = AppState(authenticationService: service)
        await appState.restoreSession()

        await appState.signOut()

        let restored = try? await service.restoreSession()
        #expect(appState.phase == .signedOut)
        #expect(restored == nil)
    }
}
