//
//  ShareService.swift
//  roomscan
//

import Foundation

protocol ShareService: Sendable {
    func loadInvitedMembers(for input: ShareScreenInput) async throws -> ShareMembersSnapshot
    func sendInvitation(for input: ShareScreenInput, email: String) async throws -> InvitedMember
    func resendInvitation(for input: ShareScreenInput, id: String) async throws -> InvitedMember
    func revokeInvitation(for input: ShareScreenInput, id: String) async throws
    func revokeAccess(for input: ShareScreenInput, userID: String) async throws
    func copyInvitationLink(for input: ShareScreenInput) async throws -> URL
}

enum ShareServiceError: Error, Equatable, Sendable {
    case offline
    case duplicateEmail
    case memberNotFound
    case unavailable
}
