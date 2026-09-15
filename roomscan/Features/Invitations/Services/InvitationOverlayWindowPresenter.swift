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

    static let overlayWindowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)

    private let makeWindow: WindowFactory
    private(set) var presentedInvitation: PendingInvitation?
    private var overlayWindow: UIWindow?
    private weak var windowToRestore: UIWindow?
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

        guard let window = makeWindow() else { return }

        if let previous = presentedInvitation, previous.id != invitation.id {
            tearDownWindow(notifyDismiss: false, restoreKeyWindow: false)
            onReplaced?(previous)
        }

        if windowToRestore == nil {
            windowToRestore = Self.currentKeyWindow(excluding: window)
        }

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

    private func tearDownWindow(notifyDismiss: Bool, restoreKeyWindow: Bool = true) {
        let dismissHandler = onDismiss
        onDismiss = nil
        presentedInvitation = nil

        guard let window = overlayWindow else {
            windowToRestore = nil
            return
        }

        overlayWindow = nil
        window.isHidden = true
        window.rootViewController = nil

        if restoreKeyWindow {
            let previous = windowToRestore
            windowToRestore = nil
            Self.preferredKeyWindow(
                from: Self.activeWindowScene()?.windows ?? [],
                previous: previous,
                excluding: window
            )?.makeKey()
        }

        if notifyDismiss {
            dismissHandler?()
        }
    }

    private static func defaultWindowFactory() -> UIWindow? {
        guard let scene = activeWindowScene() else { return nil }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = overlayWindowLevel
        window.backgroundColor = .clear
        return window
    }

    private static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
    }

    private static func currentKeyWindow(excluding overlay: UIWindow?) -> UIWindow? {
        guard let scene = activeWindowScene() else { return nil }
        if let key = scene.keyWindow, key !== overlay {
            return key
        }
        return scene.windows.first { $0 !== overlay && $0.isKeyWindow }
    }

    /// Prefers the window that was key before the overlay, then any of the app's own
    /// interactive normal-level windows. System windows (keyboard, status bar) sit
    /// above `.alert` and must not be promoted.
    static func preferredKeyWindow(
        from windows: [UIWindow],
        previous: UIWindow?,
        excluding overlay: UIWindow?
    ) -> UIWindow? {
        if let previous, isRestorableAppWindow(previous, excluding: overlay) {
            return previous
        }
        return windows.first { isRestorableAppWindow($0, excluding: overlay) }
    }

    private static func isRestorableAppWindow(_ window: UIWindow, excluding overlay: UIWindow?) -> Bool {
        window !== overlay
            && !window.isHidden
            && window.isUserInteractionEnabled
            && window.windowLevel == .normal
    }
}
