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

@MainActor
struct HomeViewInvitationOverlayTests {
    @Test func presentsOverlayOnAppearAndTearsDownOnDisappearWithoutClearingPending() async throws {
        let invitation = PendingInvitation(scope: .project, token: "home-on-appear")
        let model = HomeViewInvitationOverlayHarnessModel()
        model.pendingInvitation = invitation
        let presenter = InvitationOverlayWindowPresenter(windowFactory: makeTestWindow)
        let window = try install(HomeViewInvitationOverlayHarness(model: model, presenter: presenter))

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
        let first = PendingInvitation(scope: .project, token: "home-first")
        let second = PendingInvitation(scope: .scan, token: "home-second")
        let model = HomeViewInvitationOverlayHarnessModel()
        model.pendingInvitation = first
        let presenter = InvitationOverlayWindowPresenter(windowFactory: makeTestWindow)
        let window = try install(HomeViewInvitationOverlayHarness(model: model, presenter: presenter))

        await waitUntil { presenter.presentedInvitation == first }
        #expect(presenter.presentedInvitation == first)

        model.pendingInvitation = second
        await waitUntil { presenter.presentedInvitation == second }

        #expect(presenter.isPresented)
        #expect(presenter.presentedInvitation == second)
        #expect(model.pendingInvitation == second)

        window.rootViewController = nil
        window.isHidden = true
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
    }

    private func install(_ view: some View) throws -> UIWindow {
        let scene = try requireWindowScene()
        let host = UIHostingController(rootView: view)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .normal
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.loadViewIfNeeded()
        return window
    }

    private func requireWindowScene() throws -> UIWindowScene {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        return try #require(scene)
    }

    private func makeTestWindow() -> UIWindow? {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.windowLevel = InvitationOverlayWindowPresenter.overlayWindowLevel
        window.backgroundColor = .clear
        return window
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 500_000_000,
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while !condition() {
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
