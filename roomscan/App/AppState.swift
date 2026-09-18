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
    private(set) var pendingInvitation: PendingInvitation?
    var pendingToastMessage: String?

    let authenticationService: any AuthenticationService
    private let activityTracker: SessionActivityTracker

    init(
        authenticationService: any AuthenticationService,
        activityTracker: SessionActivityTracker? = nil
    ) {
        self.authenticationService = authenticationService
        self.activityTracker = activityTracker ?? SessionActivityTracker()
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
                if activityTracker.isSessionExpired() {
                    try await authenticationService.signOut()
                    activityTracker.clearActivity()
                    phase = .signedOut
                } else {
                    activityTracker.recordActivity()
                    phase = .authenticated(session)
                }
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
        activityTracker.recordActivity()
        phase = .authenticated(session)
    }

    /// Applies a refreshed profile, then persists a newly learned public user id so a
    /// restored session keeps it. Applying first means a sign-out during the write is not undone.
    /// Profiles for another account are ignored: a request started before a sign-out can
    /// finish after a different account has signed in.
    func updateSignedInUser(_ user: AuthenticatedUser) async {
        guard let session = currentSession, session.user.id == user.id else { return }
        applySignedInSession(AuthenticationSession(user: user, provider: session.provider))

        guard let publicUserId = user.publicUserId, publicUserId != session.user.publicUserId else {
            return
        }
        // A failed write only costs a re-fetch: the next /users/me load backfills it again.
        try? await authenticationService.storePublicUserId(publicUserId, forUserId: user.id)
    }

    func recordActivity() {
        guard isAuthenticated else { return }
        if activityTracker.isSessionExpired() {
            Task {
                await signOut()
            }
        } else {
            activityTracker.recordActivity()
        }
    }

    func signOut(showSuccessToast: Bool = false) async {
        do {
            try await authenticationService.signOut()
            activityTracker.clearActivity()
            if showSuccessToast {
                pendingToastMessage = String(localized: "account.signOut.successToast")
            }
            phase = .signedOut
        } catch {
            // Keep the existing session if sign-out fails so local data ownership stays clear.
        }
    }

    func handleSessionInvalidated() {
        activityTracker.clearActivity()
        phase = .signedOut
    }

    func consumePendingToastMessage() -> String? {
        let message = pendingToastMessage
        pendingToastMessage = nil
        return message
    }

    func retryRestore() async {
        await restoreSession()
    }

    func handleIncomingURL(_ url: URL) {
        guard let invitation = InvitationDeepLinkParser.parse(url) else { return }
        pendingInvitation = invitation
    }

    func clearPendingInvitation() {
        pendingInvitation = nil
    }
}
