//
//  ProjectSummary.swift
//  roomscan
//

import Foundation

nonisolated struct ProjectPage: Equatable, Sendable {
    let projects: [ProjectSummary]
    let hasMore: Bool
}

/// Presentation of a project's scans when remote count and local cache may disagree.
nonisolated enum ProjectScansContentState: Equatable, Sendable {
    /// No scans remotely or locally.
    case empty
    /// API reports scans, but local `roomScans` has not been loaded yet.
    case remoteOnly
    /// Local scan summaries are available.
    case local

    static func resolve(localScanCount: Int, remoteScanCount: Int) -> ProjectScansContentState {
        if localScanCount > 0 {
            return .local
        }
        if remoteScanCount > 0 {
            return .remoteOnly
        }
        return .empty
    }
}

/// Nonisolated under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` so actors and
/// tests can construct and compare this Sendable value freely.
nonisolated struct ProjectSummary: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let revision: Int
    let name: String
    let ownerName: String
    let createdAt: Date
    let updatedAt: Date
    let description: String
    let sharedUserCount: Int
    let scanCount: Int
    let roomScans: [RoomScanSummary]

    nonisolated init(
        id: String,
        revision: Int = 1,
        name: String,
        ownerName: String = "You",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        description: String = "",
        sharedUserCount: Int = 0,
        roomScans: [RoomScanSummary] = [],
        scanCount: Int? = nil
    ) {
        self.id = id
        self.revision = revision
        self.name = name
        self.ownerName = ownerName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.description = description
        self.sharedUserCount = sharedUserCount
        self.roomScans = roomScans
        self.scanCount = scanCount ?? roomScans.count
    }

    /// How scan content should be presented when API count and local cache can diverge.
    var scansContentState: ProjectScansContentState {
        .resolve(localScanCount: roomScans.count, remoteScanCount: scanCount)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case revision
        case name
        case ownerName
        case createdAt
        case updatedAt
        case description
        case sharedUserCount
        case scanCount
        case roomScans
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 1
        name = try container.decode(String.self, forKey: .name)
        ownerName = try container.decode(String.self, forKey: .ownerName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        description = try container.decode(String.self, forKey: .description)
        sharedUserCount = try container.decode(Int.self, forKey: .sharedUserCount)
        roomScans = try container.decode([RoomScanSummary].self, forKey: .roomScans)
        scanCount = try container.decodeIfPresent(Int.self, forKey: .scanCount) ?? roomScans.count
    }

    func withRoomScans(
        _ roomScans: [RoomScanSummary],
        updatedAt: Date = Date(),
        scanCountDelta: Int = 0
    ) -> ProjectSummary {
        ProjectSummary(
            id: id,
            revision: revision,
            name: name,
            ownerName: ownerName,
            createdAt: createdAt,
            updatedAt: updatedAt,
            description: description,
            sharedUserCount: sharedUserCount,
            roomScans: roomScans,
            scanCount: max(roomScans.count, max(0, scanCount + scanCountDelta))
        )
    }

    /// Prefer remote metadata; merge API scans with any richer local scan payloads.
    /// Remote `scanCount` may decrease after another device deletes scans; only clamp
    /// against the merged local list (local-only pending uploads), not the prior cache total.
    static func mergingRemoteCache(_ incoming: ProjectSummary, over existing: ProjectSummary?) -> ProjectSummary {
        guard let existing else {
            return incoming
        }
        let roomScans = ProjectAPIMapping.mergeRoomScans(
            apiScans: incoming.roomScans,
            localScans: existing.roomScans
        )
        return ProjectSummary(
            id: incoming.id,
            revision: incoming.revision,
            name: incoming.name,
            ownerName: incoming.ownerName,
            createdAt: incoming.createdAt,
            updatedAt: incoming.updatedAt,
            description: incoming.description,
            sharedUserCount: incoming.sharedUserCount,
            roomScans: roomScans,
            scanCount: max(incoming.scanCount, roomScans.count)
        )
    }

    func replacingScan(_ scan: RoomScanSummary, updatedAt: Date = Date()) -> ProjectSummary? {
        guard let scanIndex = roomScans.firstIndex(where: { $0.id == scan.id }) else { return nil }
        var roomScans = self.roomScans
        roomScans[scanIndex] = scan
        return withRoomScans(roomScans, updatedAt: updatedAt)
    }

    func removingScan(id scanID: RoomScanSummary.ID, updatedAt: Date = Date()) -> ProjectSummary {
        guard roomScans.contains(where: { $0.id == scanID }) else {
            return self
        }
        return withRoomScans(
            roomScans.filter { $0.id != scanID },
            updatedAt: updatedAt,
            scanCountDelta: -1
        )
    }
}

nonisolated struct RoomScanSummary: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let createdAt: Date
    let localModelURL: URL?
    let thumbnailName: String
    let syncStatus: RoomScanSyncStatus
    let creatorUserID: String
    let creatorDisplayName: String
    let notes: [RoomScanNoteSummary]
    /// Display count; may exceed `notes.count` when only a remote `noteCount` is known.
    let noteCount: Int
    let meshPath: String
    let thumbnailPath: String

    nonisolated init(
        id: String,
        name: String,
        createdAt: Date,
        localModelURL: URL? = nil,
        thumbnailName: String,
        syncStatus: RoomScanSyncStatus,
        creatorUserID: String = "",
        creatorDisplayName: String = "",
        notes: [RoomScanNoteSummary],
        meshPath: String? = nil,
        thumbnailPath: String? = nil,
        noteCount: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.localModelURL = localModelURL
        self.thumbnailName = thumbnailName
        self.syncStatus = syncStatus
        self.creatorUserID = creatorUserID
        self.creatorDisplayName = creatorDisplayName
        self.notes = notes
        self.noteCount = noteCount ?? notes.count
        self.meshPath = meshPath ?? "Scans/\(id)/mesh.usdz"
        self.thumbnailPath = thumbnailPath ?? "Scans/\(id)/thumbnail.jpg"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
        case localModelURL
        case thumbnailName
        case syncStatus
        case creatorUserID
        case creatorDisplayName
        case notes
        case noteCount
        case meshPath
        case thumbnailPath
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        localModelURL = try container.decodeIfPresent(URL.self, forKey: .localModelURL)
        thumbnailName = try container.decode(String.self, forKey: .thumbnailName)
        syncStatus = try container.decode(RoomScanSyncStatus.self, forKey: .syncStatus)
        creatorUserID = try container.decodeIfPresent(String.self, forKey: .creatorUserID) ?? ""
        creatorDisplayName = try container.decodeIfPresent(String.self, forKey: .creatorDisplayName) ?? ""
        notes = try container.decode([RoomScanNoteSummary].self, forKey: .notes)
        noteCount = try container.decodeIfPresent(Int.self, forKey: .noteCount) ?? notes.count
        meshPath = try container.decodeIfPresent(String.self, forKey: .meshPath)
            ?? "Scans/\(id)/mesh.usdz"
        thumbnailPath = try container.decodeIfPresent(String.self, forKey: .thumbnailPath)
            ?? "Scans/\(id)/thumbnail.jpg"
    }
}

nonisolated struct RoomScanNoteSummary: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: String
    let text: String
    let createdAt: Date
}

nonisolated enum RoomScanSyncStatus: String, CaseIterable, Codable, Equatable, Sendable {
    case pending
    case synced
    case uploading
    case failed

    /// Maps API `syncStatus` values (e.g. `PENDING`) onto the local enum.
    nonisolated static func fromAPI(_ raw: String?) -> RoomScanSyncStatus {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "SYNCED":
            return .synced
        case "UPLOADING":
            return .uploading
        case "FAILED":
            return .failed
        case "PENDING", nil:
            return .pending
        default:
            return .pending
        }
    }

    var localizedTitle: String {
        switch self {
        case .pending:
            return String(localized: "projects.scan.status.pending")
        case .synced:
            return String(localized: "projects.scan.status.synced")
        case .uploading:
            return String(localized: "projects.scan.status.uploading")
        case .failed:
            return String(localized: "projects.scan.status.failed")
        }
    }
}
