//
//  SyncIndexStore.swift
//  roomscan
//

import Foundation

/// Per-user UserDefaults index so DELETE payloads without `data` can resolve parents.
struct SyncIndexStore: Sendable {
    private static let accessPrefix = "sync.projectAccess."
    private static let assetPrefix = "sync.scanAsset."
    private static let liveAssetPrefix = "sync.scanAssetLive."

    private let userId: String?
    private let defaults: UserDefaults

    init(userId: String?, defaults: UserDefaults) {
        self.userId = userId
        self.defaults = defaults
    }

    static func clear(forUserId userId: String, defaults: UserDefaults) {
        let prefixes = [
            accessPrefix + userId + ".",
            assetPrefix + userId + ".",
            liveAssetPrefix + userId + "."
        ]
        for key in defaults.dictionaryRepresentation().keys where prefixes.contains(where: { key.hasPrefix($0) }) {
            defaults.removeObject(forKey: key)
        }
    }

    func rememberAccess(_ access: SyncProjectAccessPayload) {
        guard let key = scopedKey(prefix: Self.accessPrefix, id: access.id) else { return }
        let record = SyncAccessIndexRecord(
            projectId: access.projectId,
            userId: access.userId,
            role: access.role
        )
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key)
    }

    func rememberedAccess(id: String) -> SyncAccessIndexRecord? {
        guard let key = scopedKey(prefix: Self.accessPrefix, id: id),
              let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SyncAccessIndexRecord.self, from: data)
    }

    func forgetAccess(id: String) {
        guard let key = scopedKey(prefix: Self.accessPrefix, id: id) else { return }
        defaults.removeObject(forKey: key)
    }

    func rememberAsset(id: String, scanId: String, assetType: String?) {
        guard let key = scopedKey(prefix: Self.assetPrefix, id: id) else { return }
        let record = SyncAssetIndexRecord(scanId: scanId, assetType: assetType)
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key)
        if let liveKey = liveAssetKey(scanId: scanId, assetType: assetType) {
            defaults.set(id, forKey: liveKey)
        }
    }

    func isLiveAsset(id: String, scanId: String, assetType: String?) -> Bool {
        guard let liveKey = liveAssetKey(scanId: scanId, assetType: assetType),
              let liveId = defaults.string(forKey: liveKey), !liveId.isEmpty else {
            return true
        }
        return liveId == id
    }

    func clearLiveAsset(scanId: String, assetType: String?, matching id: String) {
        guard let liveKey = liveAssetKey(scanId: scanId, assetType: assetType),
              defaults.string(forKey: liveKey) == id else { return }
        defaults.removeObject(forKey: liveKey)
    }

    func rememberedAsset(forAssetId id: String) -> SyncAssetIndexRecord? {
        guard let key = scopedKey(prefix: Self.assetPrefix, id: id) else { return nil }
        if let data = defaults.data(forKey: key),
           let record = try? JSONDecoder().decode(SyncAssetIndexRecord.self, from: data) {
            return record
        }
        // Legacy index stored only the scan id as a plain string.
        if let scanId = defaults.string(forKey: key), !scanId.isEmpty {
            return SyncAssetIndexRecord(scanId: scanId, assetType: nil)
        }
        return nil
    }

    func forgetAsset(id: String) {
        guard let key = scopedKey(prefix: Self.assetPrefix, id: id) else { return }
        defaults.removeObject(forKey: key)
    }

    private func liveAssetKey(scanId: String, assetType: String?) -> String? {
        let type = assetType?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        guard !type.isEmpty else { return nil }
        return scopedKey(prefix: Self.liveAssetPrefix, id: scanId + "." + type)
    }

    private func scopedKey(prefix: String, id: String) -> String? {
        guard let userId, !userId.isEmpty else { return nil }
        return prefix + userId + "." + id
    }
}

struct SyncAccessIndexRecord: Codable, Equatable, Sendable {
    let projectId: String
    let userId: String
    let role: String?
}

struct SyncAssetIndexRecord: Codable, Equatable, Sendable {
    let scanId: String
    let assetType: String?
}
