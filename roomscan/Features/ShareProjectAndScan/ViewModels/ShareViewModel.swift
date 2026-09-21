//
//  ShareViewModel.swift
//  roomscan
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ShareViewModel {
    enum ViewState: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case failed
    }

    let input: ShareScreenInput

    private let service: any ShareService

    private(set) var viewState: ViewState = .idle
    private(set) var members: [InvitedMember] = []
    private(set) var isRefreshing = false
    private(set) var isInviteSheetPresented = false
    private(set) var isOffline = false
    private(set) var toastStyle: ToastStyle = .error
    private(set) var toastMessage: String?
    private(set) var errorMessage: String?
    private(set) var inviteUserID = ""
    private(set) var userIDValidationMessage: String?
    private(set) var isSendingInvite = false
    private(set) var isCopyingInvitationLink = false
    private(set) var selectedMember: InvitedMember?
    private(set) var performingMemberAction: ShareMemberAction?

    init(
        input: ShareScreenInput,
        service: any ShareService
    ) {
        self.input = input
        self.service = service
    }

    var isShareReady: Bool {
        input.isShareReady
    }

    var invitedPeopleTitle: String {
        String.localizedStringWithFormat(
            String(localized: "share.invitedPeople.title.format"),
            members.count
        )
    }

    var canInvitePeople: Bool {
        !isOffline && isShareReady
    }

    var canSendInvite: Bool {
        !isOffline && isShareReady && !isSendingInvite && !isCopyingInvitationLink
    }

    var canCopyInvitationLink: Bool {
        !isOffline && isShareReady && !isSendingInvite && !isCopyingInvitationLink
    }

    var isShowingMemberActions: Bool {
        selectedMember != nil
    }

    var isPerformingMemberAction: Bool {
        performingMemberAction != nil
    }

    func loadIfNeeded() async {
        guard viewState == .idle else { return }
        await loadMembers()
    }

    func refresh() async {
        await loadMembers(isRefreshing: true)
    }

    func retryLoad() async {
        await loadMembers()
    }

    func openInviteSheet() {
        guard canInvitePeople else {
            if isOffline {
                toastStyle = .error
                toastMessage = String(localized: "share.error.offline")
            } else if !isShareReady {
                toastStyle = .error
                toastMessage = String(localized: "share.error.syncNotReady")
            }
            return
        }
        userIDValidationMessage = nil
        inviteUserID = ""
        isInviteSheetPresented = true
    }

    func closeInviteSheet() {
        isInviteSheetPresented = false
        inviteUserID = ""
        userIDValidationMessage = nil
    }

    func dismissToast() {
        toastMessage = nil
        toastStyle = .error
    }

    func updateInviteUserID(_ value: String) {
        inviteUserID = value
        userIDValidationMessage = nil
    }

    func sendInvite() async {
        guard canSendInvite, validateInviteUserID() else { return }

        isSendingInvite = true
        let member: InvitedMember
        do {
            member = try await service.sendInvitation(
                for: input,
                publicUserID: inviteUserID.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch {
            isSendingInvite = false
            handleActionError(error, inviteInline: true)
            return
        }
        isSendingInvite = false

        withAnimation(.easeInOut(duration: 0.2)) {
            members.insert(member, at: 0)
            viewState = .loaded
        }
        toastStyle = .success
        toastMessage = String(localized: "share.toast.invitationSent")
        closeInviteSheet()

        await reloadMembersAfterInvite()
    }

    func copyInvitationLink() async {
        guard canCopyInvitationLink else { return }

        isCopyingInvitationLink = true
        defer { isCopyingInvitationLink = false }

        do {
            _ = try await service.copyInvitationLink(for: input)
            toastStyle = .success
            toastMessage = String(localized: "share.toast.linkCopied")
        } catch {
            handleActionError(error)
        }
    }

    func presentActions(for member: InvitedMember) {
        selectedMember = member
    }

    func dismissActions() {
        guard performingMemberAction == nil else { return }
        selectedMember = nil
    }

    func resendInvitation(for member: InvitedMember) async {
        await performMemberAction(.resendInvitation) {
            let updated = try await self.service.resendInvitation(for: self.input, id: member.id)
            if let index = self.members.firstIndex(where: {
                $0.id == member.id || $0.id == updated.id
            }) {
                self.members[index] = self.members[index].updatedByResend(updated)
            }
            self.toastStyle = .success
            self.toastMessage = String.localizedStringWithFormat(
                String(localized: "share.toast.invitationResent.format"),
                member.rowTitle
            )
        }
    }

    func cancelInvitation(for member: InvitedMember) async {
        await performMemberAction(.cancelInvitation) {
            try await self.service.revokeInvitation(for: self.input, id: member.id)
            withAnimation(.easeInOut(duration: 0.25)) {
                self.members.removeAll { $0.id == member.id }
                self.syncViewStateAfterMutation()
            }
            self.toastStyle = .success
            self.toastMessage = String(localized: "share.toast.invitationCancelled")
        }
    }

    func removeAccess(for member: InvitedMember) async {
        await performMemberAction(.removeAccess) {
            try await self.service.revokeAccess(for: self.input, userID: member.id)
            withAnimation(.easeInOut(duration: 0.25)) {
                self.members.removeAll { $0.id == member.id }
                self.syncViewStateAfterMutation()
            }
            self.toastStyle = .success
            self.toastMessage = String.localizedStringWithFormat(
                String(localized: "share.toast.accessRevoked.format"),
                member.rowTitle
            )
        }
    }

    private func loadMembers(isRefreshing: Bool = false) async {
        if isRefreshing {
            self.isRefreshing = true
        } else {
            viewState = .loading
        }

        defer { self.isRefreshing = false }

        do {
            let snapshot = try await service.loadInvitedMembers(for: input)
            members = snapshot.members
            self.isOffline = snapshot.isOffline
            errorMessage = nil
            viewState = snapshot.members.isEmpty ? .empty : .loaded
        } catch {
            isOffline = error.isOffline
            if isRefreshing {
                toastStyle = .error
                toastMessage = error.userFacingMessage
            } else {
                members = []
                errorMessage = error.userFacingMessage
                viewState = .failed
            }
        }
    }

    /// Format is intentionally unvalidated: the backend owns what a public user id
    /// looks like and rejects malformed values with a validation error.
    private func validateInviteUserID() -> Bool {
        let trimmedUserID = inviteUserID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedUserID.isEmpty else {
            userIDValidationMessage = String(localized: "share.validation.userId.required")
            return false
        }

        if members.contains(where: {
            $0.publicUserId?.caseInsensitiveCompare(trimmedUserID) == .orderedSame
        }) {
            userIDValidationMessage = String(localized: "share.validation.userId.duplicate")
            return false
        }

        return true
    }

    private func performMemberAction(
        _ kind: ShareMemberAction,
        _ action: @escaping @MainActor () async throws -> Void
    ) async {
        guard performingMemberAction == nil else { return }
        performingMemberAction = kind
        defer {
            performingMemberAction = nil
            selectedMember = nil
        }

        do {
            try await action()
        } catch {
            handleActionError(error)
        }
    }

    /// A failed reload keeps the optimistic row instead of contradicting the "sent" toast.
    private func reloadMembersAfterInvite() async {
        guard let snapshot = try? await service.loadInvitedMembers(for: input) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            members = snapshot.members
            isOffline = snapshot.isOffline
            syncViewStateAfterMutation()
        }
    }

    private func syncViewStateAfterMutation() {
        viewState = members.isEmpty ? .empty : .loaded
    }

    private func handleActionError(_ error: Error, inviteInline: Bool = false) {
        if inviteInline,
           let shareError = error as? ShareServiceError,
           let message = shareError.inviteValidationMessage {
            userIDValidationMessage = message
            return
        }

        if error.isOffline {
            isOffline = true
        }
        toastStyle = .error
        toastMessage = error.userFacingMessage
    }
}

private extension ShareServiceError {
    /// Failures the Owner can fix by editing the User ID, shown inline instead of as a toast.
    var inviteValidationMessage: String? {
        switch self {
        case .duplicateRecipient:
            return String(localized: "share.validation.userId.duplicate")
        case .invalidRecipient:
            return String(localized: "share.validation.userId.invalid")
        case .recipientNotFound:
            return String(localized: "share.validation.userId.notFound")
        case .cannotInviteSelf:
            return String(localized: "share.validation.userId.self")
        case .offline, .memberNotFound, .unavailable:
            return nil
        }
    }
}

private extension Error {
    var isOffline: Bool {
        guard let shareError = self as? ShareServiceError else { return false }
        return shareError == .offline
    }

    var userFacingMessage: String {
        switch self as? ShareServiceError {
        case .offline:
            return String(localized: "share.error.offline")
        case .memberNotFound:
            return String(localized: "share.error.memberNotFound")
        default:
            return String(localized: "share.error.generic")
        }
    }
}
