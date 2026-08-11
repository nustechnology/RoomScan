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
    let creatorEmail: String?
    let noteCount: Int
    let assetStatus: String
    let syncStatus: RoomScanSyncStatus
    let modelVersion: Int
    let createdAt: Date
    let updatedAt: Date
    let permissions: ScanDetailPermissions

    func updating(syncStatus: RoomScanSyncStatus) -> ScanDetail {
        ScanDetail(
            id: id,
            projectID: projectID,
            name: name,
            description: description,
            thumbnail: thumbnail,
            creatorID: creatorID,
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
    }

    struct Permissions: Decodable, Sendable {
        let role: String
        let canView: Bool
        let canEdit: Bool
        let canDelete: Bool
    }

    func toScanDetail() throws -> ScanDetail {
        ScanDetail(
            id: id,
            projectID: projectId,
            name: name,
            description: description,
            thumbnail: thumbnail,
            creatorID: creator.id,
            creatorEmail: creator.email,
            noteCount: noteCount,
            assetStatus: assetStatus,
            syncStatus: RoomScanSyncStatus(rawValue: syncStatus.lowercased()) ?? .pending,
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
