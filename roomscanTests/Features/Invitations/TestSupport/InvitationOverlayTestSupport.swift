//
//  InvitationOverlayTestSupport.swift
//  roomscanTests
//

@testable import roomscan
import SwiftUI
import Testing
import UIKit

enum InvitationOverlayTestSupport {
    static let systemWindowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 10)

    @MainActor
    static func requireWindowScene() throws -> UIWindowScene {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        return try #require(scene)
    }

    @MainActor
    static func makeWindow(
        level: UIWindow.Level,
        isHidden: Bool = false,
        isUserInteractionEnabled: Bool = true,
        windowScene: UIWindowScene? = nil
    ) -> UIWindow {
        let window: UIWindow
        if let windowScene {
            window = UIWindow(windowScene: windowScene)
        } else {
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        }
        window.windowLevel = level
        window.backgroundColor = .clear
        window.isHidden = isHidden
        window.isUserInteractionEnabled = isUserInteractionEnabled
        return window
    }

    @MainActor
    static func makeTestWindow() -> UIWindow? {
        makeWindow(level: InvitationOverlayWindowPresenter.overlayWindowLevel)
    }

    @MainActor
    static func makeKeyAppWindow(in scene: UIWindowScene) -> UIWindow {
        let window = makeWindow(level: .normal, windowScene: scene)
        window.makeKeyAndVisible()
        return window
    }

    @MainActor
    static func makeSystemLikeWindow(
        windowScene: UIWindowScene? = nil,
        isHidden: Bool = false
    ) -> UIWindow {
        makeWindow(
            level: systemWindowLevel,
            isHidden: isHidden,
            isUserInteractionEnabled: false,
            windowScene: windowScene
        )
    }

    @MainActor
    static func visibleOverlayWindow(in scene: UIWindowScene) -> UIWindow? {
        scene.windows.first { window in
            window.windowLevel == InvitationOverlayWindowPresenter.overlayWindowLevel && !window.isHidden
        }
    }

    @MainActor
    static func installHostingWindow<Content: View>(_ view: Content) throws -> UIWindow {
        let scene = try requireWindowScene()
        let host = UIHostingController(rootView: view)
        let window = makeWindow(level: .normal, windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.loadViewIfNeeded()
        return window
    }
}
