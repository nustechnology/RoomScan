//
//  KeychainTokenStore.swift
//  roomscan
//

import Foundation
import Security

// MARK: - Stored Data

struct StoredAuthData: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let userId: String
    let userEmail: String?
}

// MARK: - Errors

enum KeychainError: Error, Equatable, Sendable {
    case saveFailed(OSStatus)
    case readFailed(OSStatus)
    case deleteFailed(OSStatus)
    case unexpectedData
}

// MARK: - Protocol

protocol KeychainTokenStore: Sendable {
    func save(_ storedData: StoredAuthData) throws
    func getStoredAuthData() throws -> StoredAuthData?
    func deleteTokens() throws
}

// MARK: - Live Implementation

struct LiveKeychainTokenStore: KeychainTokenStore {
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
            return try JSONDecoder().decode(StoredAuthData.self, from: data)
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
