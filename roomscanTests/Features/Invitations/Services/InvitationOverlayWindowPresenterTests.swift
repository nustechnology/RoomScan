//
//  InvitationOverlayWindowPresenterTests.swift
//  roomscanTests
//

@testable import roomscan
import SwiftUI
import Testing
import UIKit

@MainActor
struct InvitationOverlayWindowPresenterTests {
    @Test func presentShowsOverlayAndDismissClearsIt() {
        let presenter = InvitationOverlayWindowPresenter(
            windowFactory: InvitationOverlayTestSupport.makeTestWindow
        )
        let invitation = PendingInvitation(scope: .project, token: "overlay-present")
        var dismissCount = 0

        presenter.present(
            invitation: invitation,
            onDismiss: { dismissCount += 1 },
            content: { Text("Invitation") }
        )

        #expect(presenter.isPresented)
        #expect(presenter.presentedInvitation == invitation)

        presenter.dismiss()

        #expect(!presenter.isPresented)
        #expect(presenter.presentedInvitation == nil)
        #expect(dismissCount == 1)
    }

    @Test func presentSameInvitationIsNoOp() {
        let presenter = InvitationOverlayWindowPresenter(
            windowFactory: InvitationOverlayTestSupport.makeTestWindow
        )
        let invitation = PendingInvitation(scope: .scan, token: "same-invite")
        var dismissCount = 0

        presenter.present(
            invitation: invitation,
            onDismiss: { dismissCount += 1 },
            content: { Text("First") }
        )
        presenter.present(
            invitation: invitation,
            onDismiss: { dismissCount += 1 },
            content: { Text("Second") }
        )

        #expect(presenter.isPresented)
        #expect(presenter.presentedInvitation == invitation)

        presenter.dismiss()
        #expect(dismissCount == 1)
    }

    @Test func replacingInvitationCallsOnReplacedWithoutDismiss() {
        let presenter = InvitationOverlayWindowPresenter(
            windowFactory: InvitationOverlayTestSupport.makeTestWindow
        )
        let first = PendingInvitation(scope: .project, token: "first")
        let second = PendingInvitation(scope: .project, token: "second")
        var dismissCount = 0
        var replaced: PendingInvitation?

        presenter.present(
            invitation: first,
            onDismiss: { dismissCount += 1 },
            onReplaced: { replaced = $0 },
            content: { Text("First") }
        )
        presenter.present(
            invitation: second,
            onDismiss: { dismissCount += 1 },
            onReplaced: { replaced = $0 },
            content: { Text("Second") }
        )

        #expect(replaced == first)
        #expect(dismissCount == 0)
        #expect(presenter.presentedInvitation == second)
        #expect(presenter.isPresented)

        presenter.dismissWithoutNotifying()
        #expect(dismissCount == 0)
        #expect(!presenter.isPresented)
    }

    @Test func failedReplacementWindowKeepsCurrentOverlay() {
        var remainingWindows = 1
        let presenter = InvitationOverlayWindowPresenter {
            guard remainingWindows > 0 else { return nil }
            remainingWindows -= 1
            return InvitationOverlayTestSupport.makeTestWindow()
        }
        let first = PendingInvitation(scope: .project, token: "keep-first")
        let second = PendingInvitation(scope: .project, token: "skip-second")
        var dismissCount = 0
        var replaced: PendingInvitation?

        presenter.present(
            invitation: first,
            onDismiss: { dismissCount += 1 },
            onReplaced: { replaced = $0 },
            content: { Text("First") }
        )
        presenter.present(
            invitation: second,
            onDismiss: { dismissCount += 1 },
            onReplaced: { replaced = $0 },
            content: { Text("Second") }
        )

        #expect(replaced == nil)
        #expect(dismissCount == 0)
        #expect(presenter.presentedInvitation == first)
        #expect(presenter.isPresented)

        presenter.dismiss()
        #expect(dismissCount == 1)
        #expect(!presenter.isPresented)
    }

    @Test func preferredKeyWindowRestoresPreviousAppWindowInsteadOfHigherLevelSystemWindow() {
        let appWindow = InvitationOverlayTestSupport.makeWindow(level: .normal)
        let overlay = InvitationOverlayTestSupport.makeWindow(
            level: InvitationOverlayWindowPresenter.overlayWindowLevel
        )
        let systemWindow = InvitationOverlayTestSupport.makeSystemLikeWindow()
        let hiddenAppWindow = InvitationOverlayTestSupport.makeWindow(level: .normal, isHidden: true)

        let restored = InvitationOverlayWindowPresenter.preferredKeyWindow(
            from: [systemWindow, hiddenAppWindow, overlay, appWindow],
            previous: appWindow,
            excluding: overlay
        )

        #expect(restored === appWindow)
    }

    @Test func preferredKeyWindowSkipsNonInteractiveAndHiddenWindowsWhenPreviousIsGone() {
        let overlay = InvitationOverlayTestSupport.makeWindow(
            level: InvitationOverlayWindowPresenter.overlayWindowLevel
        )
        let systemWindow = InvitationOverlayTestSupport.makeSystemLikeWindow()
        let fallback = InvitationOverlayTestSupport.makeWindow(level: .normal)

        let restored = InvitationOverlayWindowPresenter.preferredKeyWindow(
            from: [systemWindow, overlay, fallback],
            previous: nil,
            excluding: overlay
        )

        #expect(restored === fallback)
    }

    @Test func defaultFactoryPresentsAboveAlertLevelAndRestoresPreviousKeyWindow() async throws {
        let scene = try InvitationOverlayTestSupport.requireWindowScene()
        let originalKey = scene.keyWindow
        let appWindow = InvitationOverlayTestSupport.makeKeyAppWindow(in: scene)
        let systemWindow = InvitationOverlayTestSupport.makeSystemLikeWindow(windowScene: scene)

        let presenter = InvitationOverlayWindowPresenter()
        let invitation = PendingInvitation(scope: .project, token: "scene-overlay")
        var dismissCount = 0

        presenter.present(
            invitation: invitation,
            onDismiss: { dismissCount += 1 },
            content: { Text("Invitation") }
        )

        let overlay = try #require(InvitationOverlayTestSupport.visibleOverlayWindow(in: scene))
        #expect(overlay.windowLevel == InvitationOverlayWindowPresenter.overlayWindowLevel)
        #expect(overlay.isKeyWindow)
        #expect(presenter.isPresented)

        presenter.dismiss()

        #expect(!presenter.isPresented)
        #expect(dismissCount == 1)
        #expect(InvitationOverlayTestSupport.visibleOverlayWindow(in: scene) == nil)
        #expect(appWindow.isKeyWindow)
        #expect(!systemWindow.isKeyWindow)

        systemWindow.isHidden = true
        appWindow.isHidden = true
        originalKey?.makeKey()
    }

    @Test func replacingWithDefaultFactoryKeepsOriginalKeyWindowUntilFinalDismiss() async throws {
        let scene = try InvitationOverlayTestSupport.requireWindowScene()
        let originalKey = scene.keyWindow
        let appWindow = InvitationOverlayTestSupport.makeKeyAppWindow(in: scene)

        let presenter = InvitationOverlayWindowPresenter()
        let first = PendingInvitation(scope: .project, token: "scene-first")
        let second = PendingInvitation(scope: .project, token: "scene-second")
        var dismissCount = 0

        presenter.present(
            invitation: first,
            onDismiss: { dismissCount += 1 },
            content: { Text("First") }
        )
        presenter.present(
            invitation: second,
            onDismiss: { dismissCount += 1 },
            content: { Text("Second") }
        )

        #expect(dismissCount == 0)
        #expect(presenter.presentedInvitation == second)
        #expect(InvitationOverlayTestSupport.visibleOverlayWindow(in: scene)?.isKeyWindow == true)

        presenter.dismiss()

        #expect(dismissCount == 1)
        #expect(appWindow.isKeyWindow)

        appWindow.isHidden = true
        originalKey?.makeKey()
    }
}
