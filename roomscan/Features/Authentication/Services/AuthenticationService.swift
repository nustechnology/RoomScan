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
}
