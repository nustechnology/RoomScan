//
//  SharedItem.swift
//  roomscan
//

import Foundation

enum SharedItemScope: String, Equatable, Sendable {
    case project
    case scan
}

enum SharedAccessStatus: String, Equatable, CaseIterable, Sendable {
    case active
    case accessRevoked
    case itemDeleted

    nonisolated var isActive: Bool { self == .active }
}

struct SharedProjectItem: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let ownerName: String
    let scanCount: Int
    let thumbnailName: String?
    let status: SharedAccessStatus
    let statusChangedAt: Date
    /// Present for Active items so Project Details can open with full metadata.
    let detailProject: ProjectSummary?

    var isInactive: Bool { !status.isActive }

    /// Picks the thumbnail of the scan with the most recent `createdAt`.
    /// Returns `nil` when the project has no scans (UI shows the system placeholder).
    nonisolated static func thumbnailName(from roomScans: [RoomScanSummary]) -> String? {
        roomScans.max(by: { $0.createdAt < $1.createdAt })?.thumbnailName
    }

    /// Builds a shared project card from a `ProjectSummary`, deriving scan count and thumbnail.
    nonisolated static func make(
        from project: ProjectSummary,
        status: SharedAccessStatus,
        statusChangedAt: Date,
        includeDetail: Bool = true
    ) -> SharedProjectItem {
        SharedProjectItem(
            id: project.id,
            name: project.name,
            ownerName: project.ownerName,
            scanCount: project.roomScans.count,
            thumbnailName: thumbnailName(from: project.roomScans),
            status: status,
            statusChangedAt: statusChangedAt,
            detailProject: includeDetail && status.isActive ? project : nil
        )
    }
}

struct SharedScanParent: Equatable, Sendable {
    let ownerName: String
    let projectID: String
    let projectName: String
}

struct SharedScanItem: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let ownerName: String
    let noteCount: Int
    let projectID: String
    let projectName: String
    let thumbnailName: String?
    let status: SharedAccessStatus
    let statusChangedAt: Date
    /// Present for Active items so Scan Details can open with full metadata.
    let detailScan: RoomScanSummary?

    var isInactive: Bool { !status.isActive }

    /// Builds a shared scan card from a `RoomScanSummary` and parent project metadata.
    nonisolated static func make(
        from scan: RoomScanSummary,
        parent: SharedScanParent,
        status: SharedAccessStatus,
        statusChangedAt: Date,
        includeDetail: Bool = true
    ) -> SharedScanItem {
        SharedScanItem(
            id: scan.id,
            name: scan.name,
            ownerName: parent.ownerName,
            noteCount: scan.notes.count,
            projectID: parent.projectID,
            projectName: parent.projectName,
            thumbnailName: scan.thumbnailName,
            status: status,
            statusChangedAt: statusChangedAt,
            detailScan: includeDetail && status.isActive ? scan : nil
        )
    }

    nonisolated var viewerInput: ViewerInput {
        ViewerInput(
            projectID: projectID,
            projectName: projectName,
            scanID: id,
            scanName: name,
            modelURL: detailScan?.localModelURL
        )
    }
}

enum SharedServiceError: Error, Equatable {
    case network
    case notFound
}

enum SharedInactiveRetention: Sendable {
    nonisolated static let days = 7

    nonisolated static func shouldRetain(status: SharedAccessStatus, statusChangedAt: Date, now: Date = Date()) -> Bool {
        guard !status.isActive else { return true }
        let cutoff = now.addingTimeInterval(TimeInterval(-days * 86_400))
        return statusChangedAt >= cutoff
    }
}
