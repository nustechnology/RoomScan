//
//  AuthenticationService.swift
//  roomscan
//

import AuthenticationServices
import Foundation

/// Provider-neutral authentication boundary.
protocol AuthenticationService: AnyObject {
    func restoreSession() async throws -> AuthenticationSession?
    func signIn(with provider: AuthenticationProvider) async throws -> AuthenticationSession
    func signInWithApple(authorization: ASAuthorization, rawNonce: String) async throws -> AuthenticationSession
    func signOut() async throws
    /// Persists an id learned after sign-in (e.g. from `/users/me`) so restored sessions keep it.
    func storePublicUserId(_ publicUserId: String) async throws
}
