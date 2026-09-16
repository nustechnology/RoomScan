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
            let scene = try InvitationOverlayTestSupport.requireWindowScene()
            let originalKey = scene.keyWindow
            let invitation = PendingInvitation(scope: .project, token: "home-on-appear")
            let model = HomeViewInvitationOverlayHarnessModel()
            model.pendingInvitation = invitation
            let presenter = InvitationOverlayWindowPresenter(
                windowFactory: InvitationOverlayTestSupport.makeTestWindow
            )
            let window = try InvitationOverlayTestSupport.installHostingWindow(
                HomeViewInvitationOverlayHarness(model: model, presenter: presenter)
            )
            defer {
                window.rootViewController = nil
                window.isHidden = true
                originalKey?.makeKey()
            }

            await waitUntil { presenter.isPresented }

            #expect(presenter.isPresented)
            #expect(presenter.presentedInvitation == invitation)

            window.rootViewController = nil
            window.isHidden = true
            await waitUntil { !presenter.isPresented }

            #expect(!presenter.isPresented)
            #expect(model.pendingInvitation == invitation)
        }

        @Test func replacingPendingInvitationPresentsNewOverlayWithoutDismissingPrevious() async throws {
            let scene = try InvitationOverlayTestSupport.requireWindowScene()
            let originalKey = scene.keyWindow
            let first = PendingInvitation(scope: .project, token: "home-first")
            let second = PendingInvitation(scope: .scan, token: "home-second")
            let model = HomeViewInvitationOverlayHarnessModel()
            model.pendingInvitation = first
            let presenter = InvitationOverlayWindowPresenter(
                windowFactory: InvitationOverlayTestSupport.makeTestWindow
            )
            let window = try InvitationOverlayTestSupport.installHostingWindow(
                HomeViewInvitationOverlayHarness(model: model, presenter: presenter)
            )
            defer {
                window.rootViewController = nil
                window.isHidden = true
                originalKey?.makeKey()
            }

            await waitUntil { presenter.presentedInvitation == first }
            #expect(presenter.presentedInvitation == first)

            model.pendingInvitation = second
            await waitUntil { presenter.presentedInvitation == second }

            #expect(presenter.isPresented)
            #expect(presenter.presentedInvitation == second)
            #expect(model.pendingInvitation == second)
        }

        @Test func failedOverlayPresentationClearsPendingInvitation() async throws {
            let scene = try InvitationOverlayTestSupport.requireWindowScene()
            let originalKey = scene.keyWindow
            let invitation = PendingInvitation(scope: .project, token: "home-failed-present")
            let model = HomeViewInvitationOverlayHarnessModel()
            model.pendingInvitation = invitation
            let presenter = InvitationOverlayWindowPresenter { nil }
            let window = try InvitationOverlayTestSupport.installHostingWindow(
                HomeViewInvitationOverlayHarness(model: model, presenter: presenter)
            )
            defer {
                window.rootViewController = nil
                window.isHidden = true
                originalKey?.makeKey()
            }

            await waitUntil { model.pendingInvitation == nil }

            #expect(!presenter.isPresented)
            #expect(model.pendingInvitation == nil)
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

            var feedbackToastMessage: String? = "existing-toast"
            if let toast = opened.feedbackToastMessage {
                feedbackToastMessage = toast
            }
            #expect(feedbackToastMessage == "existing-toast")

            if let toast = accepted.feedbackToastMessage {
                feedbackToastMessage = toast
            }
            #expect(feedbackToastMessage == String(localized: "invitation.toast.accepted"))
        }

        private func waitUntil(
            timeoutNanoseconds: UInt64 = 500_000_000,
            _ condition: @MainActor () -> Bool
        ) async {
            let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
            while !condition() {
                if DispatchTime.now().uptimeNanoseconds >= deadline {
                    Issue.record("timed out waiting for condition")
                    return
                }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
    }
}
