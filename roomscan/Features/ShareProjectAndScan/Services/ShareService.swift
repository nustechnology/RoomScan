//
//  ShareService.swift
//  roomscan
//

import Foundation

nonisolated protocol ShareService: Sendable {
    func loadInvitedMembers(for input: ShareScreenInput) async throws -> ShareMembersSnapshot
    func sendInvitation(for input: ShareScreenInput, publicUserID: String) async throws -> InvitedMember
    func resendInvitation(for input: ShareScreenInput, id: String) async throws -> InvitedMember
    func revokeInvitation(for input: ShareScreenInput, id: String) async throws
    func revokeAccess(for input: ShareScreenInput, userID: String) async throws
    func copyInvitationLink(for input: ShareScreenInput) async throws -> URL
}

nonisolated enum ShareServiceError: Error, Equatable, Sendable {
    case offline
    case duplicateRecipient
    case invalidRecipient
    case recipientNotFound
    case cannotInviteSelf
    case memberNotFound
    case unavailable
}
