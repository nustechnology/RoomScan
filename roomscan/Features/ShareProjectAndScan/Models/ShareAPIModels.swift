//
//  ShareAPIModels.swift
//  roomscan
//

import Foundation

/// POST body for `/api/v1/projects/{projectId}/invitations`.
/// The API accepts exactly one recipient channel; this client only addresses by public user id.
nonisolated struct CreateProjectInvitationAPIRequest: Encodable, Sendable {
    let recipientPublicUserId: String
    let expiresInSeconds: Int
}

/// Shared invitation payload returned by create and resend endpoints.
/// `recipientEmail` stays decodable for invitations addressed by email before
/// this client switched to public user ids.
nonisolated struct CreateProjectInvitationAPIResponse: Decodable, Sendable {
    let invitationId: String
    let invitationUrl: String
    let recipientEmail: String?
    let recipientPublicUserId: String?
    let expiresAt: Date
    let status: String
    let sentAt: Date
}

/// Response from either project or scan share-link creation endpoint.
nonisolated struct CreateShareLinkAPIResponse: Decodable, Sendable {
    let shareLinkId: String
    let shareLinkUrl: String
    let scope: String
    let expiresAt: Date
}

/// 200 response from `DELETE /api/v1/invitations/{invitationId}`.
nonisolated struct RevokeInvitationAPIResponse: Decodable, Sendable {
    let invitationId: String
    let status: String
    let revokedAt: Date
}

/// 200 response from either project or scan share revoke endpoint.
/// The parent identifier is intentionally ignored because the caller already
/// has the share target; project APIs return `projectId` while scan APIs may
/// return `scanId`.
nonisolated struct RevokeShareAPIResponse: Decodable, Sendable {
    let userId: String
    let revokedAt: Date
}

/// GET response from `/api/v1/projects/{projectId}/shares`.
nonisolated struct ProjectSharesAPIResponse: Decodable, Sendable {
    let pendingInvitations: [PendingProjectInvitationDTO]
    let viewers: [ProjectViewerDTO]
}

nonisolated struct PendingProjectInvitationDTO: Decodable, Sendable {
    let invitationId: String
    let recipientEmail: String?
    let recipientPublicUserId: String?
    let recipientDisplayName: String?
    let status: String
    let sentAt: Date
    let expiresAt: Date
}

nonisolated struct ProjectViewerDTO: Decodable, Sendable {
    let userId: String
    let recipientUser: ProjectShareUserDTO
    let grantedAt: Date
}

nonisolated struct ProjectShareUserDTO: Decodable, Sendable {
    let id: String
    let email: String?
    let displayName: String?
    let publicUserId: String?
}

/// Nonisolated under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` so actors
/// (e.g. `RemoteShareService`) can map DTOs from any isolation domain.
nonisolated enum ShareAPIMapping {
    static func toInvitedMember(_ response: CreateProjectInvitationAPIResponse) -> InvitedMember {
        InvitedMember(
            id: response.invitationId,
            displayName: nil,
            email: nonBlank(response.recipientEmail),
            publicUserId: nonBlank(response.recipientPublicUserId),
            initials: InvitedMember.initials(
                displayName: nil,
                email: response.recipientEmail,
                publicUserId: response.recipientPublicUserId
            ),
            status: invitationStatus(from: response.status),
            sentAt: response.sentAt,
            acceptedAt: nil
        )
    }

    static func toInvitedMember(_ invitation: PendingProjectInvitationDTO) -> InvitedMember {
        InvitedMember(
            id: invitation.invitationId,
            displayName: nonBlank(invitation.recipientDisplayName),
            email: nonBlank(invitation.recipientEmail),
            publicUserId: nonBlank(invitation.recipientPublicUserId),
            initials: InvitedMember.initials(
                displayName: invitation.recipientDisplayName,
                email: invitation.recipientEmail,
                publicUserId: invitation.recipientPublicUserId
            ),
            status: invitationStatus(from: invitation.status),
            sentAt: invitation.sentAt,
            acceptedAt: nil
        )
    }

    static func toInvitedMember(_ viewer: ProjectViewerDTO) -> InvitedMember {
        InvitedMember(
            id: viewer.userId,
            displayName: nonBlank(viewer.recipientUser.displayName),
            email: nonBlank(viewer.recipientUser.email),
            publicUserId: nonBlank(viewer.recipientUser.publicUserId),
            initials: InvitedMember.initials(
                displayName: viewer.recipientUser.displayName,
                email: viewer.recipientUser.email,
                publicUserId: viewer.recipientUser.publicUserId
            ),
            status: .accepted,
            sentAt: viewer.grantedAt,
            acceptedAt: viewer.grantedAt
        )
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    static func toMembers(_ response: ProjectSharesAPIResponse) -> [InvitedMember] {
        response.pendingInvitations.map(toInvitedMember) + response.viewers.map(toInvitedMember)
    }

    static func invitationStatus(from rawValue: String) -> InvitationStatus {
        switch rawValue.uppercased() {
        case "ACCEPTED":
            return .accepted
        default:
            return .pending
        }
    }
}
