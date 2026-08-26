//
//  SyncChangeModels.swift
//  roomscan
//

import Foundation

nonisolated enum SyncResourceType: String, Codable, Equatable, Sendable {
    case project = "PROJECT"
    case scan = "SCAN"
    case note = "NOTE"
    case scanAsset = "SCAN_ASSET"
    case projectAccess = "PROJECT_ACCESS"
}

nonisolated enum SyncChangeOperation: String, Codable, Equatable, Sendable {
    case upsert = "UPSERT"
    case delete = "DELETE"
}

nonisolated enum SyncChangePayload: Equatable, Sendable {
    case project(SyncProjectPayload)
    case scan(SyncScanPayload)
    case note(SyncNotePayload)
    case scanAsset(SyncScanAssetPayload)
    case projectAccess(SyncProjectAccessPayload)
}

nonisolated struct SyncChange: Equatable, Sendable {
    let resourceId: String
    let operation: SyncChangeOperation
    /// Wire revision when present. `nil` means unknown — do not treat as stale.
    let revision: Int?
    let syncStatus: String?
    let changedAt: Date?
    let cursor: String?
    let deletedAt: Date?
    let resourceType: SyncResourceType
    let payload: SyncChangePayload?
}

nonisolated struct SyncChangesPage: Equatable, Sendable {
    let changes: [SyncChange]
    let nextCursor: String?
}

nonisolated struct SyncChangesAPIResponse: Decodable, Sendable {
    let changes: [SyncChangeAPIItem]
    let nextCursor: String?
    /// Items in `changes` that failed to decode and were dropped.
    let skippedChangeCount: Int

    enum CodingKeys: String, CodingKey {
        case changes
        case nextCursor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)

        var unkeyed = try container.nestedUnkeyedContainer(forKey: .changes)
        var decoded: [SyncChangeAPIItem] = []
        var skipped = 0
        while !unkeyed.isAtEnd {
            let wrapper = try unkeyed.decode(LossyDecodable<SyncChangeAPIItem>.self)
            if let item = wrapper.value {
                decoded.append(item)
            } else {
                skipped += 1
            }
        }
        changes = decoded
        skippedChangeCount = skipped
    }
}

/// Decodes `T` if possible; always succeeds so one bad array element does not fail the page.
private struct LossyDecodable<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(T.self)
    }
}

nonisolated struct SyncChangeAPIItem: Decodable, Sendable {
    let resourceId: String
    let operation: String
    let revision: Int?
    let syncStatus: String?
    let changedAt: Date?
    let cursor: String?
    let deletedAt: Date?
    let resourceType: String
    let payload: SyncChangePayload?

    enum CodingKeys: String, CodingKey {
        case resourceId
        case operation
        case revision
        case syncStatus
        case changedAt
        case cursor
        case deletedAt
        case resourceType
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resourceId = try container.decode(String.self, forKey: .resourceId)
        operation = try container.decode(String.self, forKey: .operation)
        revision = try Self.decodeFlexibleIntIfPresent(from: container, forKey: .revision)
        syncStatus = try container.decodeIfPresent(String.self, forKey: .syncStatus)
        changedAt = try container.decodeIfPresent(Date.self, forKey: .changedAt)
        cursor = try container.decodeIfPresent(String.self, forKey: .cursor)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        resourceType = try container.decode(String.self, forKey: .resourceType)

        let isDelete = operation.uppercased() == SyncChangeOperation.delete.rawValue
        let hasDataKey = container.contains(.data)
        let dataIsNil = hasDataKey ? (try container.decodeNil(forKey: .data)) : true
        if isDelete || dataIsNil {
            payload = nil
        } else {
            switch resourceType.uppercased() {
            case SyncResourceType.project.rawValue:
                payload = .project(try container.decode(SyncProjectPayload.self, forKey: .data))
            case SyncResourceType.scan.rawValue:
                payload = .scan(try container.decode(SyncScanPayload.self, forKey: .data))
            case SyncResourceType.note.rawValue:
                payload = .note(try container.decode(SyncNotePayload.self, forKey: .data))
            case SyncResourceType.scanAsset.rawValue:
                payload = .scanAsset(try container.decode(SyncScanAssetPayload.self, forKey: .data))
            case SyncResourceType.projectAccess.rawValue:
                payload = .projectAccess(try container.decode(SyncProjectAccessPayload.self, forKey: .data))
            default:
                payload = nil
            }
        }
    }

    private static func decodeFlexibleIntIfPresent(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Int? {
        guard container.contains(key), try !container.decodeNil(forKey: key) else { return nil }
        if let value = try? container.decode(Int.self, forKey: key) { return value }
        let stringValue = try container.decode(String.self, forKey: key)
        guard let value = Int(stringValue) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Revision must be a valid integer"
            )
        }
        return value
    }

    func toDomain() -> SyncChange? {
        guard let type = SyncResourceType(rawValue: resourceType.uppercased()) else {
            return nil
        }
        guard let op = SyncChangeOperation(rawValue: operation.uppercased()) else {
            return nil
        }
        return SyncChange(
            resourceId: resourceId,
            operation: op,
            revision: revision,
            syncStatus: syncStatus,
            changedAt: changedAt,
            cursor: cursor,
            deletedAt: deletedAt,
            resourceType: type,
            payload: payload
        )
    }
}

nonisolated struct SyncProjectPayload: Decodable, Equatable, Sendable {
    let id: String
    let ownerId: String?
    let ownerEmail: String?
    let name: String
    let description: String?
    let createdAt: Date
    let updatedAt: Date?
    let lastSyncedAt: Date?
}

nonisolated struct SyncScanPayload: Decodable, Equatable, Sendable {
    let id: String
    let projectId: String
    let createdById: String?
    let creatorEmail: String?
    let name: String
    let description: String?
    let thumbnail: String?
    let assetStatus: String?
    let modelVersion: Int?
    let createdAt: Date
    let updatedAt: Date?
    let syncStatus: String?

    enum CodingKeys: String, CodingKey {
        case id, projectId, createdById, creatorEmail, name, description
        case thumbnail, assetStatus, modelVersion, createdAt, updatedAt, syncStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        projectId = try container.decode(String.self, forKey: .projectId)
        createdById = try container.decodeIfPresent(String.self, forKey: .createdById)
        creatorEmail = try container.decodeIfPresent(String.self, forKey: .creatorEmail)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
        assetStatus = try container.decodeIfPresent(String.self, forKey: .assetStatus)
        if let intVersion = try? container.decodeIfPresent(Int.self, forKey: .modelVersion) {
            modelVersion = intVersion
        } else if let stringVersion = try container.decodeIfPresent(String.self, forKey: .modelVersion),
                  let parsed = Int(stringVersion) {
            modelVersion = parsed
        } else {
            modelVersion = nil
        }
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        syncStatus = try container.decodeIfPresent(String.self, forKey: .syncStatus)
    }
}

nonisolated struct SyncNotePayload: Decodable, Equatable, Sendable {
    let id: String
    let scanId: String
    let createdById: String?
    let creatorEmail: String?
    let title: String?
    let content: String?
    let color: String?
    let createdAt: Date
    let updatedAt: Date?
}

nonisolated struct SyncScanAssetPayload: Decodable, Equatable, Sendable {
    let id: String
    let scanId: String
    let assetType: String?
    let status: String?
    let contentType: String?
    let sizeBytes: Int?
    let checksum: String?
    let modelVersion: String?
    let uploadedAt: Date?
    let createdAt: Date?
    let updatedAt: Date?
}

nonisolated struct SyncProjectAccessPayload: Decodable, Equatable, Sendable {
    let id: String
    let projectId: String
    let userId: String
    let userEmail: String?
    let role: String?
    let acceptedAt: Date?
    let createdAt: Date?
    let updatedAt: Date?
}
