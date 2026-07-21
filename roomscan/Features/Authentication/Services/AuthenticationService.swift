//
//  AuthenticationService.swift
//  roomscan
//

import Foundation

/// Provider-neutral authentication boundary.
/// Replace `MockAuthenticationService` with a real Apple/backend implementation later.
protocol AuthenticationService: AnyObject {
    func restoreSession() async throws -> AuthenticationSession?
    func signIn(with provider: AuthenticationProvider) async throws -> AuthenticationSession
    func signOut() async throws
}
