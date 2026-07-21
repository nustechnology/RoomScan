//
//  roomscanApp.swift
//  roomscan
//

import SwiftUI

@main
struct RoomScanApp: App {
    @State private var appState: AppState

    init() {
        let authenticationService = MockAuthenticationService.makeForCurrentProcess()
        _appState = State(initialValue: AppState(authenticationService: authenticationService))
    }

    var body: some Scene {
        WindowGroup {
            AppView(appState: appState)
                .task {
                    await appState.restoreSession()
                }
        }
    }
}
