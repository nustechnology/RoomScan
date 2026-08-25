//
//  ShareAPIModels.swift
//  roomscan
//

import Foundation

/// POST body for `/api/v1/projects/{projectId}/invitations`.
struct CreateProjectInvitationAPIRequest: Encodable, Sendable {
    let recipientEmail: String
    let expiresInSeconds: Int
}

/// Shared invitation payload returned by create and resend endpoints.
struct CreateProjectInvitationAPIResponse: Decodable, Sendable {
    let invitationId: String
    let invitationUrl: String
    let recipientEmail: String
    let expiresAt: Date
    let status: String
    let sentAt: Date
}

/// Response from either project or scan share-link creation endpoint.
struct CreateShareLinkAPIResponse: Decodable, Sendable {
    let shareLinkId: String
    let shareLinkUrl: String
    let scope: String
    let expiresAt: Date
}

/// 200 response from `DELETE /api/v1/invitations/{invitationId}`.
struct RevokeInvitationAPIResponse: Decodable, Sendable {
    let invitationId: String
    let status: String
    let revokedAt: Date
}

/// 200 response from either project or scan share revoke endpoint.
/// The parent identifier is intentionally ignored because the caller already
/// has the share target; project APIs return `projectId` while scan APIs may
/// return `scanId`.
struct RevokeShareAPIResponse: Decodable, Sendable {
    let userId: String
    let revokedAt: Date
}

/// GET response from `/api/v1/projects/{projectId}/shares`.
struct ProjectSharesAPIResponse: Decodable, Sendable {
    let pendingInvitations: [PendingProjectInvitationDTO]
    let viewers: [ProjectViewerDTO]
}

struct PendingProjectInvitationDTO: Decodable, Sendable {
    let invitationId: String
    let recipientEmail: String
    let status: String
    let sentAt: Date
    let expiresAt: Date
}

struct ProjectViewerDTO: Decodable, Sendable {
    let userId: String
    let recipientUser: ProjectShareUserDTO
    let grantedAt: Date
}

struct ProjectShareUserDTO: Decodable, Sendable {
    let id: String
    let email: String
}

enum ShareAPIMapping {
    static func toInvitedMember(_ response: CreateProjectInvitationAPIResponse) -> InvitedMember {
        InvitedMember(
            id: response.invitationId,
            displayName: nil,
            email: response.recipientEmail,
            initials: InvitedMember.initials(for: response.recipientEmail),
            status: invitationStatus(from: response.status),
            sentAt: response.sentAt,
            acceptedAt: nil
        )
    }

    static func toInvitedMember(_ invitation: PendingProjectInvitationDTO) -> InvitedMember {
        InvitedMember(
            id: invitation.invitationId,
            displayName: nil,
            email: invitation.recipientEmail,
            initials: InvitedMember.initials(for: invitation.recipientEmail),
            status: invitationStatus(from: invitation.status),
            sentAt: invitation.sentAt,
            acceptedAt: nil
        )
    }

    static func toInvitedMember(_ viewer: ProjectViewerDTO) -> InvitedMember {
        let email = viewer.recipientUser.email
        return InvitedMember(
            id: viewer.userId,
            displayName: nil,
            email: email,
            initials: InvitedMember.initials(for: email),
            status: .accepted,
            sentAt: viewer.grantedAt,
            acceptedAt: viewer.grantedAt
        )
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
