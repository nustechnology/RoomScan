//
//  InvitationAPIModels.swift
//  roomscan
//

import Foundation

/// 200 response from `GET /api/v1/invitations/{token}`.
nonisolated struct InvitationPreviewAPIResponse: Decodable, Sendable {
    let type: String
    let scope: String
    let project: InvitationPreviewProjectDTO?
    let scan: InvitationPreviewScanDTO?
    let status: String
    let recipientEmail: String?
    let expiresAt: Date
    let hasAccess: Bool?
}

nonisolated struct InvitationPreviewProjectDTO: Decodable, Sendable {
    let id: String
    let name: String
    let description: String?
    let thumbnail: String?
    let owner: ProjectOwnerDTO
    let scanCount: Int
}

nonisolated struct InvitationPreviewScanDTO: Decodable, Sendable {
    let id: String
    let projectId: String
    let projectName: String?
    let name: String
    let description: String?
    let thumbnail: String?
    let noteCount: Int
    let creator: ProjectOwnerDTO
}

/// 200 response from `POST /api/v1/invitations/{token}/accept`.
nonisolated struct AcceptInvitationAPIResponse: Decodable, Sendable {
    let scope: String?
    let project: AcceptInvitationProjectDTO?
    let scan: InvitationPreviewScanDTO?
    let sentAt: Date?
    let access: AcceptInvitationAccessDTO?
}

nonisolated struct AcceptInvitationProjectDTO: Decodable, Sendable {
    let id: String
    let name: String
    let description: String?
    let thumbnail: String?
    let owner: ProjectOwnerDTO
}

nonisolated struct AcceptInvitationAccessDTO: Decodable, Sendable {
    let role: String
    let status: String
    let grantedAt: Date
}

/// 200 response from `POST /api/v1/invitations/{token}/decline`.
nonisolated struct DeclineInvitationAPIResponse: Decodable, Sendable {
    let invitationId: String
    let status: String
    let declinedAt: Date
}

nonisolated enum InvitationAPIMapping {
    nonisolated static func toInvitationDetails(
        token: String,
        scope: InvitationScope,
        response: InvitationPreviewAPIResponse
    ) throws -> InvitationDetails {
        guard InvitationScope(rawValue: response.scope.lowercased()) == scope else {
            throw InvitationServiceError.unavailable
        }

        switch scope {
        case .project:
            guard let project = response.project else {
                throw InvitationServiceError.unavailable
            }
            let summary = ProjectSummary(
                id: project.id,
                name: project.name,
                ownerName: ownerName(from: project.owner),
                description: project.description ?? "",
                sharedUserCount: 1,
                scanCount: max(0, project.scanCount)
            )

            return InvitationDetails(
                token: token,
                scope: .project,
                type: linkType(from: response),
                title: summary.name,
                ownerName: summary.ownerName,
                invitedEmail: response.recipientEmail,
                existingAccessDestination: response.hasAccess == true ? .project(summary) : nil,
                itemCount: summary.scanCount,
                showsThumbnail: hasThumbnail(project.thumbnail),
                project: summary,
                scan: nil
            )

        case .scan:
            guard let scan = response.scan else {
                throw InvitationServiceError.unavailable
            }
            let summary = toRoomScanSummary(scan, timestamp: response.expiresAt)
            let existingAccessDestination: AcceptedInvitationDestination?
            if response.hasAccess == true {
                existingAccessDestination = .scan(
                    SharedScanItem(
                        id: summary.id,
                        name: summary.name,
                        ownerName: summary.creatorDisplayName,
                        noteCount: summary.noteCount,
                        projectID: scan.projectId,
                        projectName: scan.projectName ?? "",
                        thumbnailName: summary.thumbnailName,
                        status: .active,
                        statusChangedAt: response.expiresAt,
                        detailScan: summary
                    )
                )
            } else {
                existingAccessDestination = nil
            }

            return InvitationDetails(
                token: token,
                scope: .scan,
                type: linkType(from: response),
                title: summary.name,
                ownerName: summary.creatorDisplayName,
                invitedEmail: response.recipientEmail,
                existingAccessDestination: existingAccessDestination,
                itemCount: summary.noteCount,
                showsThumbnail: hasThumbnail(scan.thumbnail),
                project: nil,
                scan: summary
            )
        }
    }

    private nonisolated static func linkType(
        from response: InvitationPreviewAPIResponse
    ) -> InvitationLinkType {
        let normalized = response.type
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        return InvitationLinkType(rawValue: normalized) ?? .invitation
    }

    private nonisolated static func hasThumbnail(_ thumbnail: String?) -> Bool {
        guard let thumbnail else { return false }
        return !thumbnail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    nonisolated static func toAcceptedDestination(
        _ response: AcceptInvitationAPIResponse,
        scope: InvitationScope
    ) throws -> AcceptedInvitationDestination {
        if let responseScope = response.scope?.lowercased(),
           InvitationScope(rawValue: responseScope) != scope {
            throw InvitationServiceError.unavailable
        }

        switch scope {
        case .project:
            guard let project = response.project else {
                throw InvitationServiceError.unavailable
            }
            return .project(
                toProjectSummary(
                    project,
                    grantedAt: response.access?.grantedAt ?? response.sentAt ?? Date()
                )
            )

        case .scan:
            guard let scan = response.scan else {
                throw InvitationServiceError.unavailable
            }
            let timestamp = response.access?.grantedAt ?? response.sentAt ?? Date()
            let summary = toRoomScanSummary(scan, timestamp: timestamp)
            return .scan(
                SharedScanItem(
                    id: summary.id,
                    name: summary.name,
                    ownerName: summary.creatorDisplayName,
                    noteCount: summary.noteCount,
                    projectID: scan.projectId,
                    projectName: scan.projectName ?? "",
                    thumbnailName: summary.thumbnailName,
                    status: .active,
                    statusChangedAt: timestamp,
                    detailScan: summary
                )
            )
        }
    }

    private nonisolated static func toRoomScanSummary(
        _ scan: InvitationPreviewScanDTO,
        timestamp: Date
    ) -> RoomScanSummary {
        RoomScanSummary(
            id: scan.id,
            name: scan.name,
            createdAt: timestamp,
            thumbnailName: "",
            syncStatus: .synced,
            creatorUserID: scan.creator.id,
            creatorDisplayName: ownerName(from: scan.creator),
            notes: [],
            thumbnailPath: scan.thumbnail ?? "",
            noteCount: max(0, scan.noteCount)
        )
    }

    private nonisolated static func ownerName(from owner: ProjectOwnerDTO) -> String {
        guard let email = owner.email?.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty
        else {
            return ""
        }
        return email
    }

    nonisolated static func toProjectSummary(
        _ project: AcceptInvitationProjectDTO,
        grantedAt: Date
    ) -> ProjectSummary {
        ProjectSummary(
            id: project.id,
            name: project.name,
            ownerName: ownerName(from: project.owner),
            createdAt: grantedAt,
            updatedAt: grantedAt,
            description: project.description ?? "",
            sharedUserCount: 1,
            roomScans: []
        )
    }
}
