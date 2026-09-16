//
//  InvitationViewModel.swift
//  roomscan
//

import Foundation
import Observation

@MainActor
@Observable
final class InvitationViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(InvitationDetails)
        case failed(InvitationServiceError)
    }

    enum BlockingAlert: Equatable, Identifiable {
        case alreadyAccepted
        case declined
        case expired
        case unavailable
        case accessDenied

        var id: String {
            switch self {
            case .alreadyAccepted:
                return "alreadyAccepted"
            case .declined:
                return "declined"
            case .expired:
                return "expired"
            case .unavailable:
                return "unavailable"
            case .accessDenied:
                return "accessDenied"
            }
        }
    }

    enum NavigationOutcome: Equatable {
        case dismissedToHome(toastMessage: String?)
        case accepted(AcceptedInvitationDestination, toastMessage: String)
        case opened(AcceptedInvitationDestination)

        var feedbackToastMessage: String? {
            switch self {
            case .dismissedToHome(let toastMessage):
                return toastMessage
            case .accepted(_, let toastMessage):
                return toastMessage
            case .opened:
                return nil
            }
        }

        /// Merges this outcome's toast (if any) onto whatever toast is already showing.
        /// Outcomes without a toast of their own (`.opened`, or `.dismissedToHome` with a
        /// nil message) must not clear one that's already on screen from a prior outcome.
        func mergedFeedbackToastMessage(current: String?) -> String? {
            feedbackToastMessage ?? current
        }
    }

    enum Action: String, Equatable {
        case accept
        case decline
    }

    struct ActionFailure: Equatable, Identifiable {
        let action: Action
        let error: InvitationServiceError

        var id: String {
            "\(action.rawValue)-\(error)"
        }
    }

    private(set) var loadState: LoadState = .idle
    private(set) var isPerformingAction = false
    private(set) var showsDeclineConfirmation = false
    private(set) var blockingAlert: BlockingAlert?
    private(set) var actionFailure: ActionFailure?
    private(set) var navigationOutcome: NavigationOutcome?

    let pendingInvitation: PendingInvitation
    private let service: any InvitationService
    private let currentUserEmail: String?

    init(
        pendingInvitation: PendingInvitation,
        service: any InvitationService,
        currentUserEmail: String?
    ) {
        self.pendingInvitation = pendingInvitation
        self.service = service
        self.currentUserEmail = currentUserEmail
    }

    var invitation: InvitationDetails? {
        if case .loaded(let details) = loadState {
            return details
        }
        return nil
    }

    var screenTitle: String {
        switch pendingInvitation.scope {
        case .project:
            return String(localized: "invitation.project.title")
        case .scan:
            return String(localized: "invitation.scan.title")
        }
    }

    var subtitleText: String? {
        guard let invitation else { return nil }
        let ownerName = invitation.ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ownerName.isEmpty else { return nil }
        switch invitation.scope {
        case .project:
            return String.localizedStringWithFormat(
                String(localized: "invitation.project.subtitle.format"),
                ownerName
            )
        case .scan:
            return String.localizedStringWithFormat(
                String(localized: "invitation.scan.subtitle.format"),
                ownerName
            )
        }
    }

    var itemCountLabel: String {
        switch pendingInvitation.scope {
        case .project:
            return String(localized: "invitation.metadata.scans")
        case .scan:
            return String(localized: "invitation.metadata.notes")
        }
    }

    var itemCountValue: String {
        guard let invitation else { return "" }
        return "\(invitation.itemCount)"
    }

    var hasExistingAccess: Bool {
        invitation?.existingAccessDestination != nil
    }

    func loadInvitation() async {
        guard loadState == .idle || isFailedLoad else { return }
        loadState = .loading
        navigationOutcome = nil
        blockingAlert = nil

        do {
            let details = try await service.fetchInvitation(
                scope: pendingInvitation.scope,
                token: pendingInvitation.token,
                currentUserEmail: currentUserEmail
            )
            loadState = .loaded(details)
        } catch let error as InvitationServiceError {
            loadState = .failed(error)
            blockingAlert = blockingAlert(for: error)
        } catch {
            loadState = .failed(.network)
        }
    }

    func requestDecline() {
        if invitation?.type == .shareLink {
            navigationOutcome = .dismissedToHome(toastMessage: nil)
            return
        }
        showsDeclineConfirmation = true
    }

    func cancelDecline() {
        showsDeclineConfirmation = false
    }

    func confirmDecline() async {
        showsDeclineConfirmation = false
        guard !isPerformingAction else { return }
        isPerformingAction = true
        actionFailure = nil
        defer { isPerformingAction = false }

        do {
            try await service.declineInvitation(
                scope: pendingInvitation.scope,
                token: pendingInvitation.token,
                currentUserEmail: currentUserEmail
            )
            navigationOutcome = .dismissedToHome(
                toastMessage: String(localized: "invitation.toast.declined")
            )
        } catch let error as InvitationServiceError {
            handleActionError(error, action: .decline)
        } catch {
            actionFailure = ActionFailure(action: .decline, error: .network)
        }
    }

    func accept() async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        actionFailure = nil
        defer { isPerformingAction = false }

        do {
            let destination = try await service.acceptInvitation(
                scope: pendingInvitation.scope,
                token: pendingInvitation.token,
                currentUserEmail: currentUserEmail
            )
            navigationOutcome = .accepted(
                destination,
                toastMessage: String(localized: "invitation.toast.accepted")
            )
        } catch let error as InvitationServiceError {
            handleActionError(error, action: .accept)
        } catch {
            actionFailure = ActionFailure(action: .accept, error: .network)
        }
    }

    func openExistingAccess() {
        guard let destination = invitation?.existingAccessDestination else { return }
        navigationOutcome = .opened(destination)
    }

    func retryFailedAction(_ failedAction: Action) async {
        actionFailure = nil

        switch failedAction {
        case .accept:
            await accept()
        case .decline:
            await confirmDecline()
        }
    }

    func dismissActionFailure() {
        actionFailure = nil
    }

    func dismissBlockingAlert() {
        guard blockingAlert != nil else { return }
        blockingAlert = nil
        navigationOutcome = .dismissedToHome(toastMessage: nil)
    }

    func clearNavigationOutcome() {
        navigationOutcome = nil
    }

    private var isFailedLoad: Bool {
        if case .failed = loadState { return true }
        return false
    }

    private func blockingAlert(for error: InvitationServiceError) -> BlockingAlert? {
        switch error {
        case .alreadyAccepted:
            return .alreadyAccepted
        case .declined:
            return .declined
        case .expired:
            return .expired
        case .unavailable:
            return .unavailable
        case .accessDenied:
            return .accessDenied
        case .network, .notFound:
            return nil
        }
    }

    private func handleActionError(_ error: InvitationServiceError, action: Action) {
        if let alert = blockingAlert(for: error) {
            blockingAlert = alert
        } else {
            actionFailure = ActionFailure(action: action, error: error)
        }
    }
}
