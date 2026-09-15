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
        let presenter = InvitationOverlayWindowPresenter(windowFactory: makeTestWindow)
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
        let presenter = InvitationOverlayWindowPresenter(windowFactory: makeTestWindow)
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
        let presenter = InvitationOverlayWindowPresenter(windowFactory: makeTestWindow)
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

    @Test func preferredKeyWindowRestoresPreviousAppWindowInsteadOfHigherLevelSystemWindow() {
        let appWindow = makeWindow(
            level: .normal,
            isHidden: false,
            isUserInteractionEnabled: true
        )
        let overlay = makeWindow(
            level: InvitationOverlayWindowPresenter.overlayWindowLevel,
            isHidden: false,
            isUserInteractionEnabled: true
        )
        let systemWindow = makeWindow(
            level: UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 10),
            isHidden: false,
            isUserInteractionEnabled: false
        )
        let hiddenAppWindow = makeWindow(
            level: .normal,
            isHidden: true,
            isUserInteractionEnabled: true
        )

        let restored = InvitationOverlayWindowPresenter.preferredKeyWindow(
            from: [systemWindow, hiddenAppWindow, overlay, appWindow],
            previous: appWindow,
            excluding: overlay
        )

        #expect(restored === appWindow)
    }

    @Test func preferredKeyWindowSkipsNonInteractiveAndHiddenWindowsWhenPreviousIsGone() {
        let overlay = makeWindow(
            level: InvitationOverlayWindowPresenter.overlayWindowLevel,
            isHidden: false,
            isUserInteractionEnabled: true
        )
        let systemWindow = makeWindow(
            level: UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 10),
            isHidden: false,
            isUserInteractionEnabled: false
        )
        let fallback = makeWindow(
            level: .normal,
            isHidden: false,
            isUserInteractionEnabled: true
        )

        let restored = InvitationOverlayWindowPresenter.preferredKeyWindow(
            from: [systemWindow, overlay, fallback],
            previous: nil,
            excluding: overlay
        )

        #expect(restored === fallback)
    }

    @Test func defaultFactoryPresentsAboveAlertLevelAndRestoresPreviousKeyWindow() async throws {
        let scene = try requireWindowScene()
        let originalKey = scene.keyWindow
        let appWindow = UIWindow(windowScene: scene)
        appWindow.windowLevel = .normal
        appWindow.backgroundColor = .clear
        appWindow.isUserInteractionEnabled = true
        appWindow.makeKeyAndVisible()

        let systemWindow = UIWindow(windowScene: scene)
        systemWindow.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 10)
        systemWindow.backgroundColor = .clear
        systemWindow.isUserInteractionEnabled = false
        systemWindow.isHidden = false

        let presenter = InvitationOverlayWindowPresenter()
        let invitation = PendingInvitation(scope: .project, token: "scene-overlay")
        var dismissCount = 0

        presenter.present(
            invitation: invitation,
            onDismiss: { dismissCount += 1 },
            content: { Text("Invitation") }
        )

        let overlay = try #require(visibleOverlayWindow(in: scene))
        #expect(overlay.windowLevel == InvitationOverlayWindowPresenter.overlayWindowLevel)
        #expect(overlay.isKeyWindow)
        #expect(presenter.isPresented)

        presenter.dismiss()

        #expect(!presenter.isPresented)
        #expect(dismissCount == 1)
        #expect(visibleOverlayWindow(in: scene) == nil)
        #expect(appWindow.isKeyWindow)
        #expect(!systemWindow.isKeyWindow)

        systemWindow.isHidden = true
        appWindow.isHidden = true
        originalKey?.makeKey()
    }

    @Test func replacingWithDefaultFactoryKeepsOriginalKeyWindowUntilFinalDismiss() async throws {
        let scene = try requireWindowScene()
        let originalKey = scene.keyWindow
        let appWindow = UIWindow(windowScene: scene)
        appWindow.windowLevel = .normal
        appWindow.backgroundColor = .clear
        appWindow.isUserInteractionEnabled = true
        appWindow.makeKeyAndVisible()

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
        #expect(visibleOverlayWindow(in: scene)?.isKeyWindow == true)

        presenter.dismiss()

        #expect(dismissCount == 1)
        #expect(appWindow.isKeyWindow)

        appWindow.isHidden = true
        originalKey?.makeKey()
    }

    private func makeTestWindow() -> UIWindow? {
        makeWindow(
            level: InvitationOverlayWindowPresenter.overlayWindowLevel,
            isHidden: false,
            isUserInteractionEnabled: true
        )
    }

    private func makeWindow(
        level: UIWindow.Level,
        isHidden: Bool,
        isUserInteractionEnabled: Bool
    ) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.windowLevel = level
        window.backgroundColor = .clear
        window.isHidden = isHidden
        window.isUserInteractionEnabled = isUserInteractionEnabled
        return window
    }

    private func requireWindowScene() throws -> UIWindowScene {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        return try #require(scene)
    }

    private func visibleOverlayWindow(in scene: UIWindowScene) -> UIWindow? {
        scene.windows.first { window in
            window.windowLevel == InvitationOverlayWindowPresenter.overlayWindowLevel && !window.isHidden
        }
    }
}
