//
//  UsersService.swift
//  roomscan
//

import Foundation

nonisolated protocol UsersService: Sendable {
    func fetchMe(fallingBackTo currentUser: AuthenticatedUser) async throws -> AuthenticatedUser
    func fetchRemoteDisplayName() async throws -> String?
    func updateMe(
        displayName: String,
        fallingBackTo currentUser: AuthenticatedUser
    ) async throws -> AuthenticatedUser
}

nonisolated enum UsersServiceError: Error, Equatable, Sendable {
    case invalidDisplayName
    case network
    case unauthorized
    case notFound
    case server
    case unavailable
}
