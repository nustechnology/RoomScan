//
//  AuthAPIModels.swift
//  roomscan
//

import Foundation

/// Nonisolated under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` so these
/// Sendable DTOs can be encoded/decoded from any isolation domain. This does
/// not move encode/decode work off the caller's actor by itself.
nonisolated struct AuthAPIRequest: Encodable, Sendable {
    let identityToken: String
    let nonce: String
}

nonisolated struct RefreshTokenAPIRequest: Encodable, Sendable {
    let refreshToken: String
}

nonisolated struct AuthAPIResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    let user: AuthUserDTO
}

nonisolated struct RefreshTokenAPIResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String?
}

nonisolated struct AuthUserDTO: Decodable, Sendable {
    let id: String
    let email: String?
    let provider: String
    let displayName: String?
    let publicUserId: String?
}
