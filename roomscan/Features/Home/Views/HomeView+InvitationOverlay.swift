//
//  HomeView+InvitationOverlay.swift
//  roomscan
//

import SwiftUI

extension HomeView {
    /// Backoff schedule (nanoseconds) for retrying a failed overlay presentation, e.g. when
    /// no foreground-active `UIWindowScene` is resolvable yet. Bounded so a persistently
    /// unpresentable invitation (backgrounded app, scene never becomes active) doesn't retry
    /// forever; `onChange(of: scenePhase)` and `onAppear` remain as event-driven retries on
    /// top of this timed backoff.
    static let invitationOverlayRetryDelaysNanoseconds: [UInt64] = [
        300_000_000, 1_000_000_000, 3_000_000_000, 5_000_000_000,
    ]

    func presentInvitationOverlay(_ invitation: PendingInvitation) {
        invitationOverlayRetryTask?.cancel()
        invitationOverlayRetryTask = nil

        if !attemptInvitationOverlayPresentation(invitation) {
            // Leave `pendingInvitation` untouched so the invite isn't silently lost, and
            // actively retry with backoff instead of only waiting for `onChange(of:
            // scenePhase)` / `onAppear` to fire again (they may not, e.g. if the app is
            // already active but momentarily has no resolvable `UIWindowScene` during a
            // scene transition).
            scheduleInvitationOverlayRetry(for: invitation, attempt: 0)
        }
    }

    /// Attempts to show `invitation`'s overlay once. Returns whether it was presented.
    @discardableResult
    func attemptInvitationOverlayPresentation(_ invitation: PendingInvitation) -> Bool {
        let didPresent = invitationOverlayPresenter.present(
            invitation: invitation,
            onDismiss: handleInvitationCoverDismissed,
            onReplaced: handleInvitationDismissed,
            content: {
                InvitationView(
                    viewModel: InvitationViewModel(
                        pendingInvitation: invitation,
                        service: invitationService,
                        currentUserEmail: session.user.email
                    ),
                    onFinished: { outcome in
                        handleInvitationFinished(outcome, for: invitation)
                    }
                )
            }
        )

        if !didPresent {
            #if DEBUG
            // Log the scope only: `invitation.id` embeds the invite token, the same
            // secret carried in the invite link, so it must not be written to the console
            // even in DEBUG builds (consistent with this codebase dropping sensitive HTTP
            // header logging elsewhere).
            print("[Invitations] failed to present overlay for a \(invitation.scope.rawValue) invitation")
            #endif
        }

        return didPresent
    }

    func scheduleInvitationOverlayRetry(for invitation: PendingInvitation, attempt: Int) {
        guard attempt < Self.invitationOverlayRetryDelaysNanoseconds.count else {
            #if DEBUG
            print("[Invitations] giving up retrying overlay for a \(invitation.scope.rawValue) invitation after \(attempt) attempts")
            #endif
            return
        }

        let delay = Self.invitationOverlayRetryDelaysNanoseconds[attempt]
        invitationOverlayRetryTask = Task {
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            // The pending invitation may have changed or been cleared while we waited
            // (e.g. resolved via a fresh `onChange`/`onAppear`/scene-phase trigger) —
            // only retry if it's still the same one waiting to be shown.
            guard pendingInvitation?.id == invitation.id, !invitationOverlayPresenter.isPresented else { return }

            if !attemptInvitationOverlayPresentation(invitation) {
                scheduleInvitationOverlayRetry(for: invitation, attempt: attempt + 1)
            }
        }
    }

    func handleInvitationFinished(
        _ outcome: InvitationViewModel.NavigationOutcome,
        for invitation: PendingInvitation
    ) {
        // `outcome` reflects a real action the user already took (an accept/decline request
        // that completed), so it must still be applied even if the overlay for `invitation`
        // is no longer the one presented — e.g. HomeView tore the overlay down via
        // `onDisappear`/`dismissWithoutNotifying()` while the request was in flight, or a
        // newer invitation replaced this one before it finished. Bailing out entirely here
        // (as we used to) silently dropped the user's action: no toast, no navigation, and
        // — because `pendingInvitation` was never cleared — the same invitation could be
        // shown again as if the user had never responded.
        if invitationOverlayPresenter.presentedInvitation?.id == invitation.id {
            invitationOverlayPresenter.dismiss()
        }
        clearPendingInvitation(matching: invitation)

        feedbackToastMessage = outcome.mergedFeedbackToastMessage(current: feedbackToastMessage)

        switch outcome {
        case .dismissedToHome:
            break
        case .accepted(let destination, _):
            acceptedInvitations.store(destination)
            Task {
                await sharedViewModel.ingestAcceptedDestination(destination)
                Task { await sharedViewModel.refreshAllContent() }
                await presentAcceptedDestinationWhenReady(destination)
            }
        case .opened(let destination):
            Task { await presentAcceptedDestinationWhenReady(destination) }
        }

        if let pendingInvitation {
            presentInvitationOverlay(pendingInvitation)
        }
    }

    func handleInvitationDismissed(_ invitation: PendingInvitation) {
        clearPendingInvitation(matching: invitation)
    }

    func clearPendingInvitation(matching invitation: PendingInvitation) {
        guard pendingInvitation?.id == invitation.id else { return }
        pendingInvitation = nil
    }

    /// Called whenever the invitation overlay window is dismissed normally (not the silent
    /// `dismissWithoutNotifying()` teardown), so a destination queued while it was showing
    /// can now be presented.
    func handleInvitationCoverDismissed() {
        flushPendingAcceptedDestinationIfReady()
    }

    /// Opens `destination` immediately, unless an invitation overlay is still occupying the
    /// screen. The overlay's `UIWindow` sits above HomeView's own window (`.alert` level vs.
    /// `.normal`), so a `fullScreenCover` triggered here would render underneath it and stay
    /// invisible until that overlay is dismissed — most concretely when a newer invitation
    /// replaces the one whose accept/decline request just completed. Queue it instead and
    /// flush it once the overlay clears.
    func presentAcceptedDestinationWhenReady(_ destination: AcceptedInvitationDestination) async {
        guard !invitationOverlayPresenter.isPresented else {
            pendingAcceptedDestination = destination
            return
        }
        await openAcceptedDestination(destination)
    }

    func flushPendingAcceptedDestinationIfReady() {
        guard !invitationOverlayPresenter.isPresented, let destination = pendingAcceptedDestination else { return }
        pendingAcceptedDestination = nil
        Task { await openAcceptedDestination(destination) }
    }

    func openAcceptedDestination(_ destination: AcceptedInvitationDestination) async {
        switch destination {
        case .project(let project):
            acceptedProject = project
        case .scan(let item):
            guard let scanDetailService else {
                acceptedViewerInput = item.viewerInput
                return
            }

            do {
                let detail = try await scanDetailService.fetchScanDetail(id: item.id)
                acceptedViewerInput = ViewerInput(
                    projectID: item.projectID,
                    projectName: item.projectName,
                    scanID: item.id,
                    scanName: detail.name,
                    modelVersion: String(detail.modelVersion),
                    modelURL: item.detailScan?.localModelURL,
                    syncStatus: detail.syncStatus,
                    assetStatus: detail.assetStatus
                )
            } catch {
                acceptedViewerInput = item.viewerInput
            }
        }
    }

    func applyAcceptedProjectScanUpdate(projectID: ProjectSummary.ID, scan: RoomScanSummary) {
        acceptedInvitations.applyUpdatedScan(projectID: projectID, scan: scan)
        projectsViewModel.applyUpdatedScan(projectID: projectID, scan: scan)
    }

    func applyAcceptedProjectScanDeletion(projectID: ProjectSummary.ID, scanID: RoomScanSummary.ID) {
        acceptedInvitations.applyDeletedScan(projectID: projectID, scanID: scanID)
        projectsViewModel.applyDeletedScan(projectID: projectID, scanID: scanID)
    }
}
