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

private protocol SharedAccessTimed {
    var status: SharedAccessStatus { get }
    var statusChangedAt: Date { get }
}

/// When either side is inactive, picks by `statusChangedAt` so a stale active event
/// cannot resurrect a revoked share. Returns `nil` when both are active.
private func preferredItemResolvingInactiveStatusConflict<Item: SharedAccessTimed>(
    existing: Item,
    incoming: Item
) -> Item? {
    guard !incoming.status.isActive || !existing.status.isActive else { return nil }
    return incoming.statusChangedAt >= existing.statusChangedAt ? incoming : existing
}

struct SharedProjectItem: Identifiable, Equatable, Sendable, SharedAccessTimed {
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
            scanCount: max(project.scanCount, project.roomScans.count),
            thumbnailName: thumbnailName(from: project.roomScans),
            status: status,
            statusChangedAt: statusChangedAt,
            detailProject: includeDetail && status.isActive ? project : nil
        )
    }

    /// Merges a prior local ingest with an incoming upsert without wiping openable detail.
    /// Active stubs (`detailProject == nil`) must not replace an active item that can open.
    nonisolated static func coalescing(
        existing: SharedProjectItem?,
        incoming: SharedProjectItem
    ) -> SharedProjectItem {
        guard let existing else { return incoming }

        if let resolved = preferredItemResolvingInactiveStatusConflict(
            existing: existing,
            incoming: incoming
        ) {
            return resolved
        }

        switch (existing.detailProject != nil, incoming.detailProject != nil) {
        case (true, false):
            return SharedProjectItem(
                id: existing.id,
                name: existing.name.isEmpty ? incoming.name : existing.name,
                ownerName: existing.ownerName.isEmpty ? incoming.ownerName : existing.ownerName,
                scanCount: max(existing.scanCount, incoming.scanCount),
                thumbnailName: existing.thumbnailName ?? incoming.thumbnailName,
                status: .active,
                statusChangedAt: max(existing.statusChangedAt, incoming.statusChangedAt),
                detailProject: existing.detailProject
            )
        case (false, true):
            return incoming
        case (true, true), (false, false):
            return incoming.statusChangedAt >= existing.statusChangedAt ? incoming : existing
        }
    }
}

struct SharedScanParent: Equatable, Sendable {
    let ownerName: String
    let projectID: String
    let projectName: String
}

struct SharedScanItem: Identifiable, Equatable, Sendable, SharedAccessTimed {
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

    /// Merges a prior local ingest with an incoming upsert without wiping openable detail.
    nonisolated static func coalescing(
        existing: SharedScanItem?,
        incoming: SharedScanItem
    ) -> SharedScanItem {
        guard let existing else { return incoming }

        if let resolved = preferredItemResolvingInactiveStatusConflict(
            existing: existing,
            incoming: incoming
        ) {
            return resolved
        }

        switch (existing.detailScan != nil, incoming.detailScan != nil) {
        case (true, false):
            return SharedScanItem(
                id: existing.id,
                name: existing.name.isEmpty ? incoming.name : existing.name,
                ownerName: existing.ownerName.isEmpty ? incoming.ownerName : existing.ownerName,
                noteCount: max(existing.noteCount, incoming.noteCount),
                projectID: existing.projectID.isEmpty ? incoming.projectID : existing.projectID,
                projectName: existing.projectName.isEmpty ? incoming.projectName : existing.projectName,
                thumbnailName: existing.thumbnailName ?? incoming.thumbnailName,
                status: .active,
                statusChangedAt: max(existing.statusChangedAt, incoming.statusChangedAt),
                detailScan: existing.detailScan
            )
        case (false, true):
            return incoming
        case (true, true), (false, false):
            return incoming.statusChangedAt >= existing.statusChangedAt ? incoming : existing
        }
    }

    nonisolated var viewerInput: ViewerInput {
        ViewerInput(
            projectID: projectID,
            projectName: projectName,
            scanID: id,
            scanName: name,
            modelURL: detailScan?.localModelURL,
            syncStatus: detailScan?.syncStatus ?? .synced,
            assetStatus: detailScan?.assetStatus
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
