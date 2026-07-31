//
//  AppStateInvitationTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

@MainActor
struct AppStateInvitationTests {
    @Test func handleIncomingURLStoresPendingInvitationWhileSignedOut() async throws {
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

        let url = try #require(URL(string: "https://roomscan.app/invite/scan/pending-token"))
        appState.handleIncomingURL(url)

        #expect(appState.phase == .signedOut)
        #expect(appState.pendingInvitation == PendingInvitation(scope: .scan, token: "pending-token"))
    }

    @Test func clearPendingInvitationRemovesStoredInvite() async throws {
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

        let url = try #require(URL(string: "roomscan://invite/project/keep-me"))
        appState.handleIncomingURL(url)
        appState.clearPendingInvitation()

        #expect(appState.pendingInvitation == nil)
    }
}
