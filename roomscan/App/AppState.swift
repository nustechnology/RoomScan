//
//  AppState.swift
//  roomscan
//

import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    enum Phase: Equatable {
        case restoring
        case signedOut
        case authenticated(AuthenticationSession)
        case restoreFailed(AuthenticationError)
    }

    private(set) var phase: Phase = .restoring

    let authenticationService: any AuthenticationService

    init(authenticationService: any AuthenticationService) {
        self.authenticationService = authenticationService
    }

    var isAuthenticated: Bool {
        if case .authenticated = phase { return true }
        return false
    }

    var currentSession: AuthenticationSession? {
        if case .authenticated(let session) = phase {
            return session
        }
        return nil
    }

    func restoreSession() async {
        phase = .restoring

        do {
            if let session = try await authenticationService.restoreSession() {
                phase = .authenticated(session)
            } else {
                phase = .signedOut
            }
        } catch let error as AuthenticationError {
            phase = .restoreFailed(error)
        } catch {
            phase = .restoreFailed(.unknown)
        }
    }

    func applySignedInSession(_ session: AuthenticationSession) {
        phase = .authenticated(session)
    }

    func signOut() async {
        do {
            try await authenticationService.signOut()
            phase = .signedOut
        } catch {
            // Keep the existing session if sign-out fails so local data ownership stays clear.
        }
    }

    func retryRestore() async {
        await restoreSession()
    }
}
