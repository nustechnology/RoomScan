//
//  InvitationModels.swift
//  roomscan
//

import Foundation

/// Nonisolated under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` so value
/// equality and hashing work from actors and nonisolated tests.
nonisolated enum InvitationScope: String, Equatable, Sendable, Hashable {
    case project
    case scan
}

/// Nonisolated under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` so value
/// equality and hashing work from actors and nonisolated tests.
nonisolated struct PendingInvitation: Equatable, Hashable, Sendable, Identifiable {
    var id: String { "\(scope.rawValue)-\(token)" }

    let scope: InvitationScope
    let token: String
}

struct InvitationDetails: Equatable, Sendable, Identifiable {
    var id: String { token }

    let token: String
    let scope: InvitationScope
    let title: String
    let ownerName: String
    /// Email the invitation was issued to; nil means any authenticated user may accept.
    let invitedEmail: String?
    let itemCount: Int
    let showsThumbnail: Bool
    let project: ProjectSummary?
    let scan: RoomScanSummary?
}

/// Nonisolated under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` so value
/// equality works from actors and nonisolated tests.
nonisolated enum AcceptedInvitationDestination: Equatable, Sendable, Identifiable {
    case project(ProjectSummary)
    case scan(SharedScanItem)

    var id: String {
        switch self {
        case .project(let project):
            return "project-\(project.id)"
        case .scan(let item):
            return "scan-\(item.id)"
        }
    }
}

struct AcceptedInvitationCollection: Equatable, Sendable {
    private(set) var destinations: [AcceptedInvitationDestination] = []

    mutating func store(_ destination: AcceptedInvitationDestination) {
        destinations.removeAll { $0.id == destination.id }
        destinations.append(destination)
    }

    mutating func applyUpdatedScan(projectID: ProjectSummary.ID, scan: RoomScanSummary) {
        guard let index = projectDestinationIndex(for: projectID) else { return }
        guard case .project(let project) = destinations[index],
              let updated = project.replacingScan(scan)
        else {
            return
        }
        destinations[index] = .project(updated)
    }

    mutating func applyRenamedScan(scanID: String, name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard let index = scanDestinationIndex(for: scanID),
              case .scan(let item) = destinations[index]
        else {
            return
        }
        let renamedDetail = item.detailScan.map { detail in
            RoomScanSummary(
                id: detail.id,
                name: trimmedName,
                createdAt: detail.createdAt,
                localModelURL: detail.localModelURL,
                thumbnailName: detail.thumbnailName,
                syncStatus: detail.syncStatus,
                creatorUserID: detail.creatorUserID,
                creatorDisplayName: detail.creatorDisplayName,
                notes: detail.notes,
                meshPath: detail.meshPath,
                thumbnailPath: detail.thumbnailPath,
                noteCount: detail.noteCount
            )
        }
        destinations[index] = .scan(
            SharedScanItem(
                id: item.id,
                name: trimmedName,
                ownerName: item.ownerName,
                noteCount: item.noteCount,
                projectID: item.projectID,
                projectName: item.projectName,
                thumbnailName: item.thumbnailName,
                status: item.status,
                statusChangedAt: item.statusChangedAt,
                detailScan: renamedDetail
            )
        )
    }

    mutating func applyDeletedScan(projectID: ProjectSummary.ID, scanID: RoomScanSummary.ID) {
        guard let index = projectDestinationIndex(for: projectID) else { return }
        guard case .project(let project) = destinations[index] else { return }
        destinations[index] = .project(project.removingScan(id: scanID))
    }

    private func projectDestinationIndex(for projectID: ProjectSummary.ID) -> Int? {
        destinations.firstIndex { destination in
            if case .project(let project) = destination {
                return project.id == projectID
            }
            return false
        }
    }

    private func scanDestinationIndex(for scanID: String) -> Int? {
        destinations.firstIndex { destination in
            if case .scan(let item) = destination {
                return item.id == scanID
            }
            return false
        }
    }
}

enum InvitationServiceError: Error, Equatable, Sendable {
    case expired
    case unavailable
    case accessDenied
    case network
    case notFound
}

enum InvitationDeepLinkParser {
    nonisolated static func parse(_ url: URL) -> PendingInvitation? {
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        if url.scheme == "roomscan" {
            // roomscan://invite/project/{token}
            guard url.user == nil,
                  url.password == nil,
                  url.port == nil,
                  url.host == "invite",
                  pathComponents.count == 2,
                  let scope = InvitationScope(rawValue: pathComponents[0])
            else {
                return nil
            }
            return PendingInvitation(scope: scope, token: pathComponents[1])
        }

        // https://roomscan.app/invite/project/{token}
        guard url.scheme == "https",
              url.user == nil,
              url.password == nil,
              url.port == nil,
              let host = url.host,
              host == "roomscan.app" || host == "www.roomscan.app",
              pathComponents.count == 3,
              pathComponents[0] == "invite",
              let scope = InvitationScope(rawValue: pathComponents[1])
        else {
            return nil
        }
        return PendingInvitation(scope: scope, token: pathComponents[2])
    }
}
