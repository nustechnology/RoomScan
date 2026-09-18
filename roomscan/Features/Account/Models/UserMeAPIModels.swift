//
//  UserMeAPIModels.swift
//  roomscan
//

import Foundation

nonisolated struct UpdateUserMeAPIRequest: Encodable, Sendable {
    let displayName: String
}

/// Response for GET/PATCH `/api/v1/users/me`.
/// Real payloads may omit `id`, use `userId`, or wrap fields under `user` / `data`.
/// Nonisolated under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` so actors can
/// map responses from any isolation domain (does not offload decode by itself).
nonisolated struct UserMeAPIResponse: Decodable, Sendable {
    let id: String?
    let email: String?
    let displayName: String?
    let provider: String?
    let publicUserId: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case userId
        case email
        case displayName
        case provider
        case publicUserId
        case user
        case data
    }

    init(
        id: String? = nil,
        email: String? = nil,
        displayName: String? = nil,
        provider: String? = nil,
        publicUserId: String? = nil
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.provider = provider
        self.publicUserId = publicUserId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.user),
           let nested = try? container.nestedContainer(keyedBy: CodingKeys.self, forKey: .user) {
            self = try Self.decodeFields(from: nested)
            return
        }

        if container.contains(.data),
           let nested = try? container.nestedContainer(keyedBy: CodingKeys.self, forKey: .data) {
            self = try Self.decodeFields(from: nested)
            return
        }

        self = try Self.decodeFields(from: container)
    }

    func toAuthenticatedUser(fallingBackTo current: AuthenticatedUser) -> AuthenticatedUser {
        let resolvedID = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedPublicUserId = publicUserId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return AuthenticatedUser(
            id: resolvedID.isEmpty ? current.id : resolvedID,
            displayName: displayName ?? current.displayName,
            email: email ?? current.email,
            publicUserId: resolvedPublicUserId.isEmpty ? current.publicUserId : resolvedPublicUserId
        )
    }

    private static func decodeFields(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> UserMeAPIResponse {
        let id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .userId)
        let email = try container.decodeIfPresent(String.self, forKey: .email)
        let displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        let provider = try container.decodeIfPresent(String.self, forKey: .provider)
        let publicUserId = try container.decodeIfPresent(String.self, forKey: .publicUserId)
        return UserMeAPIResponse(
            id: id,
            email: email,
            displayName: displayName,
            provider: provider,
            publicUserId: publicUserId
        )
    }
}
