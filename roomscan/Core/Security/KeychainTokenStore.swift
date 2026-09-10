//
//  KeychainTokenStore.swift
//  roomscan
//

import Foundation
import Security

// MARK: - Stored Data

/// Nonisolated under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` so actors
/// (e.g. `AccessTokenRefreshCoordinator`) can read/write tokens from any isolation domain.
nonisolated struct StoredAuthData: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let userId: String
    let userEmail: String?
    let userDisplayName: String?
    let needsDisplayNameUpload: Bool

    init(
        accessToken: String,
        refreshToken: String,
        userId: String,
        userEmail: String?,
        userDisplayName: String?,
        needsDisplayNameUpload: Bool = false
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.userId = userId
        self.userEmail = userEmail
        self.userDisplayName = userDisplayName
        self.needsDisplayNameUpload = needsDisplayNameUpload
    }

    func withNeedsDisplayNameUpload(_ value: Bool) -> StoredAuthData {
        StoredAuthData(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userId: userId,
            userEmail: userEmail,
            userDisplayName: userDisplayName,
            needsDisplayNameUpload: value
        )
    }

    func withRefreshedTokens(accessToken: String, refreshToken: String) -> StoredAuthData {
        StoredAuthData(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userId: userId,
            userEmail: userEmail,
            userDisplayName: userDisplayName,
            needsDisplayNameUpload: needsDisplayNameUpload
        )
    }

    private enum CodingKeys: String, CodingKey {
        case accessToken
        case refreshToken
        case userId
        case userEmail
        case userDisplayName
        case needsDisplayNameUpload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decode(String.self, forKey: .refreshToken)
        userId = try container.decode(String.self, forKey: .userId)
        userEmail = try container.decodeIfPresent(String.self, forKey: .userEmail)
        userDisplayName = try container.decodeIfPresent(String.self, forKey: .userDisplayName)
        needsDisplayNameUpload = try container.decodeIfPresent(Bool.self, forKey: .needsDisplayNameUpload) ?? false
    }
}

// MARK: - Errors

nonisolated enum KeychainError: Error, Equatable, Sendable {
    case saveFailed(OSStatus)
    case readFailed(OSStatus)
    case deleteFailed(OSStatus)
    case unexpectedData
}

// MARK: - Protocol

nonisolated protocol KeychainTokenStore: Sendable {
    func save(_ storedData: StoredAuthData) throws
    func getStoredAuthData() throws -> StoredAuthData?
    func deleteTokens() throws
}

// MARK: - Live Implementation

nonisolated struct LiveKeychainTokenStore: KeychainTokenStore {
    private let service = "com.nus.roomscan.auth"
    private let account = "authSession"

    func save(_ storedData: StoredAuthData) throws {
        let data = try JSONEncoder().encode(storedData)

        try? deleteTokens()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }

    }

    func getStoredAuthData() throws -> StoredAuthData? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.readFailed(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.unexpectedData
        }

        do {
            let storedData = try JSONDecoder().decode(StoredAuthData.self, from: data)
            return storedData
        } catch {
            throw KeychainError.unexpectedData
        }
    }

    func deleteTokens() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}
