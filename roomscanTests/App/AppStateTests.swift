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
