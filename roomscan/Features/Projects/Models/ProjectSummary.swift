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
nonisolated struct ProjectSummary: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let ownerName: String
    let createdAt: Date
    let updatedAt: Date
    let description: String
    let sharedUserCount: Int
    let roomScans: [RoomScanSummary]

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
        guard roomScans.contains(where: { $0.id == scanID }) else { return self }
        return withRoomScans(roomScans.filter { $0.id != scanID }, updatedAt: updatedAt)
    }
}

nonisolated struct RoomScanSummary: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let createdAt: Date
    let localModelURL: URL?
    let thumbnailName: String
    let syncStatus: RoomScanSyncStatus
    let creatorUserID: String
    let creatorDisplayName: String
    let notes: [RoomScanNoteSummary]
}

nonisolated struct RoomScanNoteSummary: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let text: String
    let createdAt: Date
}

nonisolated enum RoomScanSyncStatus: String, CaseIterable, Equatable, Sendable {
    case synced
    case uploading
    case failed

    var localizedTitle: String {
        switch self {
        case .synced:
            return String(localized: "projects.scan.status.synced")
        case .uploading:
            return String(localized: "projects.scan.status.uploading")
        case .failed:
            return String(localized: "projects.scan.status.failed")
        }
    }
}
