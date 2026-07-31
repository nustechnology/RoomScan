//
//  roomscanApp.swift
//  roomscan
//

import FirebaseCore
import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

@main
struct RoomScanApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var appState: AppState

    init() {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-UITesting")
        let authenticationService: any AuthenticationService = isUITesting
            ? MockAuthenticationService.makeForCurrentProcess()
            : FirebaseAuthenticationService()

        _appState = State(initialValue: AppState(authenticationService: authenticationService))
    }

    var body: some Scene {
        WindowGroup {
            AppView(appState: appState)
                .task {
                    await appState.restoreSession()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        appState.recordActivity()
                    }
                }
                .onOpenURL { url in
                    appState.handleIncomingURL(url)
                }
        }
    }
}
