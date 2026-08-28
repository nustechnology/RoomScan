//
//  AuthAPIModels.swift
//  roomscan
//

import Foundation

struct AuthAPIRequest: Encodable, Sendable {
    let identityToken: String
    let nonce: String
}

struct RefreshTokenAPIRequest: Encodable, Sendable {
    let refreshToken: String
}

struct AuthAPIResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    let user: AuthUserDTO
}

struct RefreshTokenAPIResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String?
}

struct AuthUserDTO: Decodable, Sendable {
    let id: String
    let email: String?
    let provider: String
    let displayName: String?
}
