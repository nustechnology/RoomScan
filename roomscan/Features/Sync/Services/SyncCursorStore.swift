//
//  SyncCursorStore.swift
//  roomscan
//

import Foundation

nonisolated protocol SyncCursorStoring: Sendable {
    func cursor(forUserId userId: String) async -> String?
    func save(cursor: String?, forUserId userId: String) async
    func clear(forUserId userId: String) async
}

/// Serializes cursor reads/writes through actor isolation so concurrent callers
/// cannot interleave updates to the same UserDefaults keys.
actor SyncCursorStore: SyncCursorStoring {
    private nonisolated static let defaultsKeyPrefix = "sync.changes.cursor."

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func cursor(forUserId userId: String) -> String? {
        let value = defaults.string(forKey: Self.key(for: userId))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    func save(cursor: String?, forUserId userId: String) {
        let key = Self.key(for: userId)
        let trimmed = cursor?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            defaults.set(trimmed, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func clear(forUserId userId: String) {
        defaults.removeObject(forKey: Self.key(for: userId))
    }

    private nonisolated static func key(for userId: String) -> String {
        defaultsKeyPrefix + userId
    }
}
