//
//  AuthenticationModels.swift
//  roomscan
//

import Foundation

enum AuthenticationProvider: String, Codable, Sendable, CaseIterable {
    case apple
    case google
    case facebook
}

struct AuthenticatedUser: Equatable, Codable, Sendable, Identifiable {
    let id: String
    let displayName: String?
    let email: String?
}

struct AuthenticationSession: Equatable, Codable, Sendable {
    let user: AuthenticatedUser
    let provider: AuthenticationProvider
}

enum AuthenticationError: Error, Equatable, Sendable, LocalizedError {
    case cancelled
    case appleSystemError
    case invalidCredential
    case networkError
    case unavailable
    case unknown

    var errorDescription: String? {
        switch self {
        case .cancelled:
            String(localized: "auth.error.cancelled")
        case .appleSystemError:
            String(localized: "auth.error.appleSystem")
        case .invalidCredential:
            String(localized: "auth.error.invalidCredential")
        case .networkError:
            String(localized: "auth.error.network")
        case .unavailable:
            String(localized: "auth.error.unavailable")
        case .unknown:
            String(localized: "auth.error.unknown")
        }
    }
}
