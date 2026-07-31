//
//  InvitationService.swift
//  roomscan
//

import Foundation

protocol InvitationService: Sendable {
    func fetchInvitation(
        scope: InvitationScope,
        token: String,
        currentUserEmail: String?
    ) async throws -> InvitationDetails

    func acceptInvitation(
        scope: InvitationScope,
        token: String,
        currentUserEmail: String?
    ) async throws -> AcceptedInvitationDestination

    func declineInvitation(
        scope: InvitationScope,
        token: String
    ) async throws
}
