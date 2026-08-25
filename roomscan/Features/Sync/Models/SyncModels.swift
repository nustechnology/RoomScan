//
//  SyncModels.swift
//  roomscan
//

import Foundation

nonisolated enum ProjectSyncReadinessStatus: String, Codable, Equatable, Sendable {
    case pending = "PENDING"
    case syncing = "SYNCING"
    case synced = "SYNCED"
    case failed = "FAILED"
    case conflict = "CONFLICT"

    nonisolated static func fromAPI(_ raw: String?) -> ProjectSyncReadinessStatus {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "SYNCING":
            return .syncing
        case "SYNCED":
            return .synced
        case "FAILED":
            return .failed
        case "CONFLICT":
            return .conflict
        case "PENDING", nil:
            return .pending
        default:
            return .pending
        }
    }
}

nonisolated struct ProjectSyncStatusSummary: Identifiable, Equatable, Sendable {
    var id: String { projectId }

    let projectId: String
    let syncStatus: ProjectSyncReadinessStatus
    let pendingCount: Int
    let syncingCount: Int
    let failedCount: Int
    let conflictCount: Int
    let lastSyncedAt: Date?
    let requiredAssetsUploaded: Bool

    var unresolvedCount: Int {
        pendingCount + syncingCount + failedCount + conflictCount
    }
}

nonisolated struct SyncStatusAPIResponse: Decodable, Sendable {
    let items: [ProjectSyncStatusAPIItem]
}

nonisolated struct ProjectSyncStatusAPIItem: Decodable, Sendable {
    let projectId: String
    let syncStatus: String
    let pendingCount: Int
    let syncingCount: Int
    let failedCount: Int
    let conflictCount: Int
    let lastSyncedAt: Date?
    let requiredAssetsUploaded: Bool

    enum CodingKeys: String, CodingKey {
        case projectId
        case syncStatus
        case pendingCount
        case syncingCount
        case failedCount
        case conflictCount
        case lastSyncedAt
        case requiredAssetsUploaded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectId = try container.decode(String.self, forKey: .projectId)
        syncStatus = try container.decode(String.self, forKey: .syncStatus)
        pendingCount = try container.decodeIfPresent(Int.self, forKey: .pendingCount) ?? 0
        syncingCount = try container.decodeIfPresent(Int.self, forKey: .syncingCount) ?? 0
        failedCount = try container.decodeIfPresent(Int.self, forKey: .failedCount) ?? 0
        conflictCount = try container.decodeIfPresent(Int.self, forKey: .conflictCount) ?? 0
        lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        requiredAssetsUploaded = try container.decodeIfPresent(Bool.self, forKey: .requiredAssetsUploaded) ?? false
    }

    func toSummary() -> ProjectSyncStatusSummary {
        ProjectSyncStatusSummary(
            projectId: projectId,
            syncStatus: ProjectSyncReadinessStatus.fromAPI(syncStatus),
            pendingCount: pendingCount,
            syncingCount: syncingCount,
            failedCount: failedCount,
            conflictCount: conflictCount,
            lastSyncedAt: lastSyncedAt,
            requiredAssetsUploaded: requiredAssetsUploaded
        )
    }
}

enum SyncServiceError: Error, Equatable, Sendable {
    case network
    case unauthorized
    case notFound
    case invalidRequest
    case rateLimited
    case decoding
    case server
}

enum SyncApplyError: Error, Equatable, Sendable {
    case missingParent
    case incompleteChange
    case persistFailed
}
