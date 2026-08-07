//
//  ProjectSummary.swift
//  roomscan
//

import Foundation

struct ProjectPage: Equatable, Sendable {
    let projects: [ProjectSummary]
    let hasMore: Bool
}

/// Nonisolated under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` so actors and
/// tests can construct and compare this Sendable value freely.
nonisolated struct ProjectSummary: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let name: String
    let ownerName: String
    let createdAt: Date
    let updatedAt: Date
    let description: String
    let sharedUserCount: Int
    let roomScans: [RoomScanSummary]

    nonisolated init(
        id: String,
        name: String,
        ownerName: String = "You",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        description: String = "",
        sharedUserCount: Int = 0,
        roomScans: [RoomScanSummary] = []
    ) {
        self.id = id
        self.name = name
        self.ownerName = ownerName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.description = description
        self.sharedUserCount = sharedUserCount
        self.roomScans = roomScans
    }

    func withRoomScans(_ roomScans: [RoomScanSummary], updatedAt: Date = Date()) -> ProjectSummary {
        ProjectSummary(
            id: id,
            name: name,
            ownerName: ownerName,
            createdAt: createdAt,
            updatedAt: updatedAt,
            description: description,
            sharedUserCount: sharedUserCount,
            roomScans: roomScans
        )
    }

    func replacingScan(_ scan: RoomScanSummary, updatedAt: Date = Date()) -> ProjectSummary? {
        guard let scanIndex = roomScans.firstIndex(where: { $0.id == scan.id }) else { return nil }
        var roomScans = self.roomScans
        roomScans[scanIndex] = scan
        return withRoomScans(roomScans, updatedAt: updatedAt)
    }

    func removingScan(id scanID: RoomScanSummary.ID, updatedAt: Date = Date()) -> ProjectSummary {
        withRoomScans(roomScans.filter { $0.id != scanID }, updatedAt: updatedAt)
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
        thumbnailPath: String? = nil
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
        self.meshPath = meshPath ?? "Scans/\(id)/mesh.usdz"
        self.thumbnailPath = thumbnailPath ?? "Scans/\(id)/thumbnail.jpg"
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
