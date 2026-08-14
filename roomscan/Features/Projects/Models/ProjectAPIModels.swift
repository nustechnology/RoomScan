//
//  ProjectAPIModels.swift
//  roomscan
//

import Foundation

struct CreateProjectAPIRequest: Encodable, Sendable {
    let name: String
    /// JSON key is `description`. Named to avoid `CustomStringConvertible.description` clashes.
    let projectDescription: String?

    enum CodingKeys: String, CodingKey {
        case name
        case projectDescription = "description"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(projectDescription, forKey: .projectDescription)
    }
}

/// PATCH body for `/api/v1/projects/{projectId}`.
struct UpdateProjectAPIRequest: Encodable, Sendable {
    let name: String
    /// JSON key is `description`. Named to avoid `CustomStringConvertible.description` clashes.
    let projectDescription: String?

    enum CodingKeys: String, CodingKey {
        case name
        case projectDescription = "description"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(projectDescription, forKey: .projectDescription)
    }
}

/// POST body for `/api/v1/projects/{projectId}/scans`.
struct CreateScanAPIRequest: Encodable, Sendable {
    let name: String
    let thumbnail: ScanAssetMetadataRequest
    let scanFile: ScanAssetMetadataRequest
}

struct ScanAssetMetadataRequest: Encodable, Sendable {
    let contentType: String
    let sizeBytes: Int
    let checksum: String?
    let modelVersion: String?

    private enum CodingKeys: String, CodingKey {
        case contentType
        case sizeBytes
        case checksum
        case modelVersion
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contentType, forKey: .contentType)
        try container.encode(sizeBytes, forKey: .sizeBytes)
        try container.encodeIfPresent(checksum, forKey: .checksum)
        try container.encodeIfPresent(modelVersion, forKey: .modelVersion)
    }
}

/// Response from creating a scan. Each asset has a presigned URL to upload its binary data.
struct CreateScanAPIResponse: Decodable, Sendable {
    let id: String
    let uploads: ScanUploadURLs
}

struct ScanUploadURLs: Decodable, Sendable {
    let thumbnail: PresignedUploadTarget
    let scanFile: PresignedUploadTarget
}

struct PresignedUploadTarget: Decodable, Sendable {
    let uploadSessionId: String
    let uploadUrl: URL
}

struct UploadCompletionAPIRequest: Encodable, Sendable {
    let sizeBytes: Int
    let checksum: String?

    private enum CodingKeys: String, CodingKey {
        case sizeBytes
        case checksum
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sizeBytes, forKey: .sizeBytes)
        try container.encodeIfPresent(checksum, forKey: .checksum)
    }
}

/// POST body for `/api/v1/upload-sessions/{uploadSessionId}/fail`.
struct UploadFailureAPIRequest: Encodable, Sendable {
    let reason: String
}

/// POST body for `/api/v1/scans/{scanId}/assets/upload-sessions`.
struct CreateAssetUploadSessionAPIRequest: Encodable, Sendable {
    let assetType: String
    let contentType: String
    let sizeBytes: Int
    let checksum: String?
    let modelVersion: String?

    private enum CodingKeys: String, CodingKey {
        case assetType
        case contentType
        case sizeBytes
        case checksum
        case modelVersion
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(assetType, forKey: .assetType)
        try container.encode(contentType, forKey: .contentType)
        try container.encode(sizeBytes, forKey: .sizeBytes)
        try container.encodeIfPresent(checksum, forKey: .checksum)
        try container.encodeIfPresent(modelVersion, forKey: .modelVersion)
    }
}

struct ProjectAPIResponse: Decodable, Sendable, Equatable {
    let id: String
    let name: String
    let description: String?
    let owner: ProjectOwnerDTO
    let scanCount: Int
    let scans: [ProjectScanDTO]?
    let sharedCount: Int
    let thumbnail: String?
    let syncStatus: String?
    let createdAt: Date
    let updatedAt: Date
    let permissions: ProjectPermissionsDTO
}

/// Nested scan summary on project create/list/detail/update responses.
struct ProjectScanDTO: Decodable, Sendable, Equatable {
    let id: String
    let name: String
    let description: String?
    let thumbnail: String?
    let noteCount: Int
    let assetStatus: String?
    let syncStatus: String?
    let createdAt: Date
}

struct ProjectOwnerDTO: Decodable, Sendable, Equatable {
    let id: String
    let email: String?
}

struct ProjectPermissionsDTO: Decodable, Sendable, Equatable {
    let role: String
    let canView: Bool
    let canEdit: Bool
    let canDelete: Bool
    let canShare: Bool
    let canCreateScan: Bool
}

enum ProjectAPIMapping {
    nonisolated static func toProjectSummary(
        _ response: ProjectAPIResponse,
        preservingRoomScans localScans: [RoomScanSummary] = []
    ) -> ProjectSummary {
        let apiScans = (response.scans ?? []).map(toRoomScanSummary)
        let roomScans = mergeRoomScans(apiScans: apiScans, localScans: localScans)
        return ProjectSummary(
            id: response.id,
            name: response.name,
            ownerName: response.owner.email.flatMap { $0.isEmpty ? nil : $0 } ?? "You",
            createdAt: response.createdAt,
            updatedAt: response.updatedAt,
            description: response.description ?? "",
            sharedUserCount: response.sharedCount,
            roomScans: roomScans,
            scanCount: max(response.scanCount, roomScans.count)
        )
    }

    nonisolated static func toProjectPage(_ response: ProjectsListAPIResponse) -> ProjectPage {
        let projects = response.items.map { toProjectSummary($0) }
        let hasMore = response.pagination.page < response.pagination.totalPages
        return ProjectPage(projects: projects, hasMore: hasMore)
    }

    nonisolated static func toRoomScanSummary(_ scan: ProjectScanDTO) -> RoomScanSummary {
        RoomScanSummary(
            id: scan.id,
            name: scan.name,
            createdAt: scan.createdAt,
            thumbnailName: "",
            syncStatus: RoomScanSyncStatus.fromAPI(scan.syncStatus),
            notes: [],
            thumbnailPath: scan.thumbnail ?? "",
            noteCount: max(0, scan.noteCount)
        )
    }

    /// Prefer API scan list when present; overlay local mesh/notes for matching IDs;
    /// keep local-only scans (e.g. pending upload) that the API has not listed yet.
    nonisolated static func mergeRoomScans(
        apiScans: [RoomScanSummary],
        localScans: [RoomScanSummary]
    ) -> [RoomScanSummary] {
        guard !apiScans.isEmpty else {
            return localScans
        }

        let localByID = Dictionary(uniqueKeysWithValues: localScans.map { ($0.id, $0) })
        var merged = apiScans.map { remote in
            guard let local = localByID[remote.id] else {
                return remote
            }
            return RoomScanSummary(
                id: remote.id,
                name: remote.name.isEmpty ? local.name : remote.name,
                createdAt: remote.createdAt,
                localModelURL: local.localModelURL,
                thumbnailName: local.thumbnailName,
                syncStatus: preferredSyncStatus(local: local.syncStatus, remote: remote.syncStatus),
                creatorUserID: local.creatorUserID,
                creatorDisplayName: local.creatorDisplayName,
                notes: local.notes,
                meshPath: local.meshPath,
                thumbnailPath: preferredThumbnailPath(local: local.thumbnailPath, remote: remote.thumbnailPath),
                noteCount: max(remote.noteCount, local.noteCount, local.notes.count)
            )
        }

        let apiIDs = Set(apiScans.map(\.id))
        let localOnly = localScans.filter { !apiIDs.contains($0.id) }
        merged.append(contentsOf: localOnly)
        return merged
    }

    nonisolated private static func preferredSyncStatus(
        local: RoomScanSyncStatus,
        remote: RoomScanSyncStatus
    ) -> RoomScanSyncStatus {
        switch local {
        case .uploading, .failed:
            return local
        case .pending, .synced:
            return remote
        }
    }

    nonisolated private static func preferredThumbnailPath(local: String, remote: String) -> String {
        if local.hasPrefix("http://") || local.hasPrefix("https://") {
            return remote.isEmpty ? local : remote
        }
        if !local.isEmpty {
            return local
        }
        return remote
    }
}

struct ProjectsListAPIResponse: Decodable, Sendable, Equatable {
    let items: [ProjectAPIResponse]
    let pagination: ProjectsPaginationDTO
}

struct ProjectsPaginationDTO: Decodable, Sendable, Equatable {
    let page: Int
    let limit: Int
    let total: Int
    let totalPages: Int
}
