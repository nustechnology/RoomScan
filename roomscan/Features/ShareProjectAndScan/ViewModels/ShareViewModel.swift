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
    private(set) var inviteEmail = ""
    private(set) var emailValidationMessage: String?
    private(set) var isSendingInvite = false
    private(set) var isCopyingInvitationLink = false
    private(set) var selectedMember: InvitedMember?
    private(set) var performingMemberAction: ShareMemberAction?

    init(input: ShareScreenInput, service: any ShareService) {
        self.input = input
        self.service = service
    }

    var invitedPeopleTitle: String {
        String.localizedStringWithFormat(
            String(localized: "share.invitedPeople.title.format"),
            members.count
        )
    }

    var canInvitePeople: Bool {
        !isOffline
    }

    var canSendInvite: Bool {
        !isOffline && !isSendingInvite && !isCopyingInvitationLink
    }

    var canCopyInvitationLink: Bool {
        !isOffline && !isSendingInvite && !isCopyingInvitationLink
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
        guard canInvitePeople else { return }
        emailValidationMessage = nil
        inviteEmail = ""
        isInviteSheetPresented = true
    }

    func closeInviteSheet() {
        isInviteSheetPresented = false
        inviteEmail = ""
        emailValidationMessage = nil
    }

    func dismissToast() {
        toastMessage = nil
        toastStyle = .error
    }

    func updateInviteEmail(_ value: String) {
        inviteEmail = value
        emailValidationMessage = nil
    }

    func sendInvite() async {
        guard canSendInvite, validateInviteEmail() else { return }

        isSendingInvite = true
        defer { isSendingInvite = false }

        do {
            let member = try await service.sendInvitation(
                for: input,
                email: inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            withAnimation(.easeInOut(duration: 0.2)) {
                members.insert(member, at: 0)
                viewState = .loaded
            }
            toastStyle = .success
            toastMessage = String(localized: "share.toast.invitationSent")
            closeInviteSheet()
        } catch {
            handleActionError(error, duplicateInline: true)
        }
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
                self.members[index] = updated
            }
            self.toastStyle = .success
            self.toastMessage = String.localizedStringWithFormat(
                String(localized: "share.toast.invitationResent.format"),
                member.email
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

    private func validateInviteEmail() -> Bool {
        let trimmedEmail = inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty else {
            emailValidationMessage = String(localized: "share.validation.email.required")
            return false
        }

        guard Self.isValidEmail(trimmedEmail) else {
            emailValidationMessage = String(localized: "share.validation.email.invalid")
            return false
        }

        if members.contains(where: { $0.email.caseInsensitiveCompare(trimmedEmail) == .orderedSame }) {
            emailValidationMessage = String(localized: "share.validation.email.duplicate")
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

    private func syncViewStateAfterMutation() {
        viewState = members.isEmpty ? .empty : .loaded
    }

    private func handleActionError(_ error: Error, duplicateInline: Bool = false) {
        if duplicateInline,
           let shareError = error as? ShareServiceError,
           shareError == .duplicateEmail {
            emailValidationMessage = String(localized: "share.validation.email.duplicate")
            return
        }

        if error.isOffline {
            isOffline = true
        }
        toastStyle = .error
        toastMessage = error.userFacingMessage
    }

    private static func isValidEmail(_ value: String) -> Bool {
        let pattern = #"^[A-Z0-9a-z._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return value.range(of: pattern, options: .regularExpression) != nil
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
        case .duplicateEmail:
            return String(localized: "share.validation.email.duplicate")
        case .memberNotFound:
            return String(localized: "share.error.memberNotFound")
        default:
            return String(localized: "share.error.generic")
        }
    }
}
