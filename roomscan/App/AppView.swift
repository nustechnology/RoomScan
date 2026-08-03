//
//  AppView.swift
//  roomscan
//

import SwiftUI

struct AppView: View {
    @Bindable var appState: AppState

    var body: some View {
        // SplashScreenView()

        Group {
            switch appState.phase {
            case .restoring:
                SplashScreenView()

            case .signedOut:
                AuthenticationView(appState: appState)

            case .authenticated(let session):
                HomeView(
                    session: session,
                    projectsService: MockProjectsService.makeForCurrentProcess(),
                    sharedService: MockSharedService.makeForCurrentProcess()
                ) {
                    Task {
                        await appState.signOut()
                    }
                }

            case .restoreFailed(let error):
                ContentUnavailableView {
                    Label(String(localized: "app.restoreFailed.title"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button(String(localized: "app.restoreFailed.retry")) {
                        Task {
                            await appState.retryRestore()
                        }
                    }
                    .accessibilityIdentifier("app.restoreRetry")
                }
            }
        }
        .animation(.default, value: appState.phase)
    }
}
