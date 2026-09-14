//
//  InvitationOverlayWindowPresenter.swift
//  roomscan
//

import SwiftUI
import UIKit

/// Presents invitation UI in a dedicated `UIWindow` above SwiftUI sheets / fullScreenCovers.
@MainActor
final class InvitationOverlayWindowPresenter {
    typealias WindowFactory = @MainActor () -> UIWindow?

    private let makeWindow: WindowFactory
    private(set) var presentedInvitation: PendingInvitation?
    private var overlayWindow: UIWindow?
    private var onDismiss: (() -> Void)?

    var isPresented: Bool {
        overlayWindow != nil
    }

    init(windowFactory: @escaping WindowFactory) {
        makeWindow = windowFactory
    }

    convenience init() {
        self.init(windowFactory: Self.defaultWindowFactory)
    }

    /// Shows `content` for `invitation` above the app's existing modal stack.
    /// Replacing an already-presented invite tears down the previous window without
    /// invoking `onDismiss` (caller receives the previous invite via `onReplaced`).
    func present<Content: View>(
        invitation: PendingInvitation,
        onDismiss: @escaping () -> Void,
        onReplaced: ((PendingInvitation) -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        if presentedInvitation?.id == invitation.id, isPresented {
            return
        }

        if let previous = presentedInvitation, previous.id != invitation.id {
            tearDownWindow(notifyDismiss: false)
            onReplaced?(previous)
        }

        guard let window = makeWindow() else { return }

        let hostingController = UIHostingController(rootView: content())
        hostingController.view.backgroundColor = .systemBackground

        window.rootViewController = hostingController
        window.makeKeyAndVisible()

        overlayWindow = window
        presentedInvitation = invitation
        self.onDismiss = onDismiss
    }

    /// Hides the overlay and invokes the dismiss handler registered at present time.
    func dismiss() {
        tearDownWindow(notifyDismiss: true)
    }

    /// Hides the overlay without invoking the dismiss handler (e.g. HomeView teardown).
    func dismissWithoutNotifying() {
        tearDownWindow(notifyDismiss: false)
    }

    private func tearDownWindow(notifyDismiss: Bool) {
        let dismissHandler = onDismiss
        onDismiss = nil
        presentedInvitation = nil

        let window = overlayWindow
        overlayWindow = nil
        window?.isHidden = true
        window?.rootViewController = nil

        Self.restoreKeyWindow(excluding: window)

        if notifyDismiss {
            dismissHandler?()
        }
    }

    private static func defaultWindowFactory() -> UIWindow? {
        guard let scene = activeWindowScene() else { return nil }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
        window.backgroundColor = .clear
        return window
    }

    private static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
    }

    private static func restoreKeyWindow(excluding overlay: UIWindow?) {
        guard let scene = activeWindowScene() else { return }
        let candidate = scene.windows
            .filter { $0 !== overlay && !$0.isHidden }
            .sorted { lhs, rhs in
                lhs.windowLevel.rawValue > rhs.windowLevel.rawValue
            }
            .first
        candidate?.makeKey()
    }
}
