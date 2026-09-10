//
//  ScanDetail.swift
//  roomscan
//

import Foundation

nonisolated struct ScanDetail: Sendable {
    let id: String
    let projectID: String
    let name: String
    let description: String?
    let thumbnail: String?
    let creatorID: String
    let creatorDisplayName: String?
    let creatorEmail: String?
    let noteCount: Int
    let assetStatus: String
    let syncStatus: RoomScanSyncStatus
    let modelVersion: Int
    let createdAt: Date
    let updatedAt: Date
    let permissions: ScanDetailPermissions

    init(
        id: String,
        projectID: String,
        name: String,
        description: String?,
        thumbnail: String?,
        creatorID: String,
        creatorDisplayName: String? = nil,
        creatorEmail: String?,
        noteCount: Int,
        assetStatus: String,
        syncStatus: RoomScanSyncStatus,
        modelVersion: Int,
        createdAt: Date,
        updatedAt: Date,
        permissions: ScanDetailPermissions
    ) {
        self.id = id
        self.projectID = projectID
        self.name = name
        self.description = description
        self.thumbnail = thumbnail
        self.creatorID = creatorID
        self.creatorDisplayName = creatorDisplayName
        self.creatorEmail = creatorEmail
        self.noteCount = noteCount
        self.assetStatus = assetStatus
        self.syncStatus = syncStatus
        self.modelVersion = modelVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.permissions = permissions
    }

    func updating(syncStatus: RoomScanSyncStatus) -> ScanDetail {
        ScanDetail(
            id: id,
            projectID: projectID,
            name: name,
            description: description,
            thumbnail: thumbnail,
            creatorID: creatorID,
            creatorDisplayName: creatorDisplayName,
            creatorEmail: creatorEmail,
            noteCount: noteCount,
            assetStatus: assetStatus,
            syncStatus: syncStatus,
            modelVersion: modelVersion,
            createdAt: createdAt,
            updatedAt: updatedAt,
            permissions: permissions
        )
    }
}

nonisolated struct ScanDetailPermissions: Sendable {
    let role: String
    let canView: Bool
    let canEdit: Bool
    let canDelete: Bool
}

struct ScanDetailUpdateRequest: Encodable, Sendable {
    let name: String
    let description: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case description
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
    }
}

struct ScanDetailAPIResponse: Decodable, Sendable {
    let id: String
    let revision: Int?
    let projectId: String
    let name: String
    let description: String?
    let thumbnail: String?
    let creator: Creator
    let noteCount: Int
    let assetStatus: String
    let syncStatus: String
    let modelVersion: Int
    let createdAt: String
    let updatedAt: String
    let permissions: Permissions

    struct Creator: Decodable, Sendable {
        let id: String
        let email: String?
        let displayName: String?
    }

    struct Permissions: Decodable, Sendable {
        let role: String
        let canView: Bool
        let canEdit: Bool
        let canDelete: Bool
    }

    private enum CodingKeys: String, CodingKey {
        case id, revision, projectId, name, description, thumbnail, creator
        case noteCount, assetStatus, syncStatus, modelVersion, createdAt, updatedAt
        case permissions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        revision = try container.decodeFlexibleIntIfPresent(forKey: .revision)
        projectId = try container.decode(String.self, forKey: .projectId)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
        creator = try container.decode(Creator.self, forKey: .creator)
        noteCount = try container.decode(Int.self, forKey: .noteCount)
        assetStatus = try container.decode(String.self, forKey: .assetStatus)
        syncStatus = try container.decode(String.self, forKey: .syncStatus)
        modelVersion = try container.decode(Int.self, forKey: .modelVersion)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        permissions = try container.decode(Permissions.self, forKey: .permissions)
    }

    func toScanDetail() throws -> ScanDetail {
        ScanDetail(
            id: id,
            projectID: projectId,
            name: name,
            description: description,
            thumbnail: thumbnail,
            creatorID: creator.id,
            creatorDisplayName: creator.displayName,
            creatorEmail: creator.email,
            noteCount: noteCount,
            assetStatus: assetStatus,
            syncStatus: RoomScanSyncStatus.fromAPI(syncStatus),
            modelVersion: modelVersion,
            createdAt: try Self.parseDate(createdAt),
            updatedAt: try Self.parseDate(updatedAt),
            permissions: ScanDetailPermissions(
                role: permissions.role,
                canView: permissions.canView,
                canEdit: permissions.canEdit,
                canDelete: permissions.canDelete
            )
        )
    }

    private static func parseDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: value) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Invalid ISO-8601 date: \(value)")
            )
        }
        return date
    }
}
