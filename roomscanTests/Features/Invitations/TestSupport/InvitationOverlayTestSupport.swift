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

    /// Installs `view` as a hosting window's root, runs `body` with that window, then tears
    /// the window down and restores whatever was the key window before it was installed.
    /// Centralizes the resolve-scene / save-key / install / teardown boilerplate that
    /// window-based overlay tests would otherwise each repeat.
    @MainActor
    static func withHostingWindow<Content: View>(
        _ view: Content,
        _ body: @MainActor (UIWindow) async throws -> Void
    ) async throws {
        let scene = try requireWindowScene()
        let originalKey = scene.keyWindow
        let window = try installHostingWindow(view)
        defer {
            window.rootViewController = nil
            window.isHidden = true
            originalKey?.makeKey()
        }
        try await body(window)
    }

    /// Polls `condition` until it's true or `timeoutNanoseconds` elapses, recording a test
    /// failure on timeout. Shared by the overlay tests so their retry timings stay consistent.
    @MainActor
    static func waitUntil(
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
