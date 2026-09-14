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

    private func makeTestWindow() -> UIWindow? {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
        window.backgroundColor = .clear
        return window
    }
}
