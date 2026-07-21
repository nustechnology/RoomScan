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
    case unavailable
    case unknown

    var errorDescription: String? {
        switch self {
        case .cancelled:
            String(localized: "auth.error.cancelled")
        case .unavailable:
            String(localized: "auth.error.unavailable")
        case .unknown:
            String(localized: "auth.error.unknown")
        }
    }
}
