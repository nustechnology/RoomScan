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
    let revision: Int?
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

    private enum CodingKeys: String, CodingKey {
        case id, revision, name, description, owner, scanCount, scans, sharedCount
        case thumbnail, syncStatus, createdAt, updatedAt, permissions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        revision = try container.decodeFlexibleIntIfPresent(forKey: .revision)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        owner = try container.decode(ProjectOwnerDTO.self, forKey: .owner)
        scanCount = try container.decode(Int.self, forKey: .scanCount)
        scans = try container.decodeIfPresent([ProjectScanDTO].self, forKey: .scans)
        sharedCount = try container.decode(Int.self, forKey: .sharedCount)
        thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
        syncStatus = try container.decodeIfPresent(String.self, forKey: .syncStatus)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        permissions = try container.decode(ProjectPermissionsDTO.self, forKey: .permissions)
    }
}

extension KeyedDecodingContainer {
    func decodeFlexibleIntIfPresent(forKey key: Key) throws -> Int? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        if let value = try? decode(Int.self, forKey: key) { return value }
        let stringValue = try decode(String.self, forKey: key)
        guard let value = Int(stringValue) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Revision must be a valid integer"
            )
        }
        return value
    }
}

/// Nested scan summary on project create/list/detail/update responses.
struct ProjectScanDTO: Decodable, Sendable, Equatable {
    let id: String
    let revision: Int?
    let name: String
    let description: String?
    let thumbnail: String?
    let noteCount: Int
    let assetStatus: String?
    let syncStatus: String?
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, revision, name, description, thumbnail, noteCount
        case assetStatus, syncStatus, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        revision = try container.decodeFlexibleIntIfPresent(forKey: .revision)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
        noteCount = try container.decode(Int.self, forKey: .noteCount)
        assetStatus = try container.decodeIfPresent(String.self, forKey: .assetStatus)
        syncStatus = try container.decodeIfPresent(String.self, forKey: .syncStatus)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

struct ProjectOwnerDTO: Decodable, Sendable, Equatable {
    let id: String
    let email: String?
    let displayName: String?
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
        revision: Int? = nil,
        preservingRoomScans localScans: [RoomScanSummary] = []
    ) -> ProjectSummary {
        let apiScans = (response.scans ?? []).map(toRoomScanSummary)
        let roomScans = mergeRoomScans(apiScans: apiScans, localScans: localScans)
        return ProjectSummary(
            id: response.id,
            revision: revision ?? response.revision ?? 1,
            name: response.name,
            ownerName: ownerName(from: response.owner),
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

    private nonisolated static func ownerName(from owner: ProjectOwnerDTO) -> String {
        for value in [owner.displayName, owner.email] {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
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
            noteCount: max(0, scan.noteCount),
            assetStatus: scan.assetStatus
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
            let notes = mergedNotes(local: local.notes, incoming: remote.notes)
            return RoomScanSummary(
                id: remote.id,
                name: remote.name.isEmpty ? local.name : remote.name,
                createdAt: remote.createdAt,
                localModelURL: local.localModelURL,
                thumbnailName: local.thumbnailName,
                syncStatus: preferredSyncStatus(
                    local: local.syncStatus,
                    remote: remote.syncStatus,
                    hasLocalUploadArtifacts: local.hasLocalUploadArtifacts
                ),
                creatorUserID: local.creatorUserID,
                creatorDisplayName: local.creatorDisplayName,
                notes: notes,
                meshPath: local.meshPath,
                thumbnailPath: preferredThumbnailPath(local: local.thumbnailPath, remote: remote.thumbnailPath),
                noteCount: max(
                    remote.noteCount,
                    local.noteCount,
                    local.notes.count,
                    remote.notes.count,
                    notes.count
                ),
                assetStatus: preferredAssetStatus(local: local.assetStatus, remote: remote.assetStatus)
            )
        }

        let apiIDs = Set(apiScans.map(\.id))
        let localOnly = localScans.filter { !apiIDs.contains($0.id) }
        merged.append(contentsOf: localOnly)
        return merged
    }

    nonisolated private static func mergedNotes(
        local: [RoomScanNoteSummary],
        incoming: [RoomScanNoteSummary]
    ) -> [RoomScanNoteSummary] {
        var byID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for note in incoming {
            byID[note.id] = note
        }
        return byID.values.sorted {
            $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt
        }
    }

    /// Keep in-flight uploads sticky; keep Failed/Conflict while a mesh remains for retry.
    /// Do not sticky-keep `.pending` — device-created scans persist `.pending` with a mesh URL
    /// that is deliberately retained after a successful upload, so mesh presence is not an
    /// outstanding-upload signal. Otherwise trust the remote scan `syncStatus`.
    nonisolated static func preferredSyncStatus(
        local: RoomScanSyncStatus,
        remote: RoomScanSyncStatus,
        hasLocalUploadArtifacts: Bool
    ) -> RoomScanSyncStatus {
        switch local {
        case .uploading:
            return .uploading
        case .failed, .conflict:
            return hasLocalUploadArtifacts ? local : remote
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

    nonisolated private static func preferredAssetStatus(local: String?, remote: String?) -> String? {
        let trimmedRemote = remote?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedRemote, !trimmedRemote.isEmpty {
            return trimmedRemote
        }
        let trimmedLocal = local?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedLocal, !trimmedLocal.isEmpty {
            return trimmedLocal
        }
        return nil
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
