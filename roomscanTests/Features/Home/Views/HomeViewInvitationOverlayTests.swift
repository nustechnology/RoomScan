//
//  HomeViewInvitationOverlayTests.swift
//  roomscanTests
//

@testable import roomscan
import SwiftUI
import Testing
import UIKit

@MainActor
@Observable
private final class HomeViewInvitationOverlayHarnessModel {
    var pendingInvitation: PendingInvitation?
}

private struct HomeViewInvitationOverlayHarness: View {
    @Bindable var model: HomeViewInvitationOverlayHarnessModel
    let presenter: InvitationOverlayWindowPresenter

    var body: some View {
        HomeView(
            session: .mockAppleUser,
            projectsService: MockProjectsService(simulatedDelayNanoseconds: 0),
            notesService: MockNotesService(),
            shareService: MockShareService(simulatedDelayNanoseconds: 0),
            sharedService: MockSharedService(simulatedDelayNanoseconds: 0),
            syncService: MockSyncService(simulatedDelayNanoseconds: 0),
            usersService: MockUsersService(),
            invitationService: LocalInvitationService(simulatedDelayNanoseconds: 0),
            overlayPresenter: presenter,
            pendingInvitation: $model.pendingInvitation,
            onSignOut: {}
        )
    }
}

extension InvitationOverlaySceneTests {
    @Suite
    @MainActor
    struct HomeViewOverlay {
        @Test func presentsOverlayOnAppearAndTearsDownOnDisappearWithoutClearingPending() async throws {
            let invitation = PendingInvitation(scope: .project, token: "home-on-appear")
            let model = HomeViewInvitationOverlayHarnessModel()
            model.pendingInvitation = invitation
            let presenter = InvitationOverlayWindowPresenter(
                windowFactory: InvitationOverlayTestSupport.makeTestWindow
            )

            try await InvitationOverlayTestSupport.withHostingWindow(
                HomeViewInvitationOverlayHarness(model: model, presenter: presenter)
            ) { window in
                await InvitationOverlayTestSupport.waitUntil { presenter.isPresented }

                #expect(presenter.isPresented)
                #expect(presenter.presentedInvitation == invitation)

                window.rootViewController = nil
                window.isHidden = true
                await InvitationOverlayTestSupport.waitUntil { !presenter.isPresented }

                #expect(!presenter.isPresented)
                #expect(model.pendingInvitation == invitation)
            }
        }

        @Test func replacingPendingInvitationPresentsNewOverlayWithoutDismissingPrevious() async throws {
            let first = PendingInvitation(scope: .project, token: "home-first")
            let second = PendingInvitation(scope: .scan, token: "home-second")
            let model = HomeViewInvitationOverlayHarnessModel()
            model.pendingInvitation = first
            let presenter = InvitationOverlayWindowPresenter(
                windowFactory: InvitationOverlayTestSupport.makeTestWindow
            )

            try await InvitationOverlayTestSupport.withHostingWindow(
                HomeViewInvitationOverlayHarness(model: model, presenter: presenter)
            ) { _ in
                await InvitationOverlayTestSupport.waitUntil { presenter.presentedInvitation == first }
                #expect(presenter.presentedInvitation == first)

                model.pendingInvitation = second
                await InvitationOverlayTestSupport.waitUntil { presenter.presentedInvitation == second }

                #expect(presenter.isPresented)
                #expect(presenter.presentedInvitation == second)
                #expect(model.pendingInvitation == second)
            }
        }

        @Test func failedOverlayPresentationLeavesPendingInvitationForRetry() async throws {
            let invitation = PendingInvitation(scope: .project, token: "home-failed-present")
            let model = HomeViewInvitationOverlayHarnessModel()
            model.pendingInvitation = invitation
            var presentAttempts = 0
            let presenter = InvitationOverlayWindowPresenter {
                presentAttempts += 1
                return nil
            }

            try await InvitationOverlayTestSupport.withHostingWindow(
                HomeViewInvitationOverlayHarness(model: model, presenter: presenter)
            ) { _ in
                await InvitationOverlayTestSupport.waitUntil { presentAttempts > 0 }

                // A window-factory failure must not drop the invitation: it stays pending
                // (rather than being cleared) so it's still there for the automatic backoff
                // retry and the `onChange(of: scenePhase)` / `onAppear` triggers to present.
                #expect(!presenter.isPresented)
                #expect(model.pendingInvitation == invitation)
            }
        }

        @Test func failedOverlayPresentationRetriesWithBackoffUntilWindowFactoryRecovers() async throws {
            let invitation = PendingInvitation(scope: .project, token: "home-retry-succeeds")
            let model = HomeViewInvitationOverlayHarnessModel()
            model.pendingInvitation = invitation
            var presentAttempts = 0
            let presenter = InvitationOverlayWindowPresenter {
                presentAttempts += 1
                // Fail the initial attempt (from `onAppear`) so the backoff retry kicks in,
                // then succeed once that retry fires.
                guard presentAttempts > 1 else { return nil }
                return InvitationOverlayTestSupport.makeTestWindow()
            }

            try await InvitationOverlayTestSupport.withHostingWindow(
                HomeViewInvitationOverlayHarness(model: model, presenter: presenter)
            ) { _ in
                // The first backoff delay is 300ms; give it real headroom.
                await InvitationOverlayTestSupport.waitUntil(timeoutNanoseconds: 2_000_000_000) {
                    presenter.isPresented
                }

                // A window-factory failure must lead to an actual retry, not just a
                // silently-preserved pending value: the overlay ends up presented once
                // the factory recovers, without any new trigger from the view (no further
                // `onAppear`/`onChange(of: pendingInvitation)`).
                #expect(presentAttempts >= 2)
                #expect(presenter.isPresented)
                #expect(presenter.presentedInvitation == invitation)
                #expect(model.pendingInvitation == invitation)
            }
        }

        @Test func dismissedOutcomePropagatesOptionalToastMessage() {
            let dismissedWithoutToast = InvitationViewModel.NavigationOutcome.dismissedToHome(toastMessage: nil)
            let dismissedWithToast = InvitationViewModel.NavigationOutcome.dismissedToHome(
                toastMessage: String(localized: "invitation.toast.declined")
            )
            let accepted = InvitationViewModel.NavigationOutcome.accepted(
                .project(
                    ProjectSummary(
                        id: "toast-project",
                        name: "Toast Project",
                        ownerName: "Owner",
                        description: "",
                        sharedUserCount: 1,
                        scanCount: 0
                    )
                ),
                toastMessage: String(localized: "invitation.toast.accepted")
            )
            let opened = InvitationViewModel.NavigationOutcome.opened(
                .project(
                    ProjectSummary(
                        id: "existing-project",
                        name: "Existing Project",
                        ownerName: "Owner",
                        description: "",
                        sharedUserCount: 1,
                        scanCount: 0
                    )
                )
            )

            #expect(dismissedWithoutToast.feedbackToastMessage == nil)
            #expect(dismissedWithToast.feedbackToastMessage == String(localized: "invitation.toast.declined"))
            #expect(accepted.feedbackToastMessage == String(localized: "invitation.toast.accepted"))
            #expect(opened.feedbackToastMessage == nil)

            // Exercise the actual production merge (`HomeView.handleInvitationFinished` calls
            // this same method) rather than re-implementing the branch here: an outcome with
            // no toast of its own must preserve whatever was already showing, while one that
            // carries a toast replaces it.
            #expect(opened.mergedFeedbackToastMessage(current: "existing-toast") == "existing-toast")
            #expect(dismissedWithoutToast.mergedFeedbackToastMessage(current: "existing-toast") == "existing-toast")
            #expect(
                accepted.mergedFeedbackToastMessage(current: "existing-toast")
                    == String(localized: "invitation.toast.accepted")
            )
            #expect(
                dismissedWithToast.mergedFeedbackToastMessage(current: "existing-toast")
                    == String(localized: "invitation.toast.declined")
            )
        }
    }
}
