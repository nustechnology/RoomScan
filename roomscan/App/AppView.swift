//
//  AppView.swift
//  roomscan
//

import SwiftUI

struct AppView: View {
    @Bindable var appState: AppState
    let projectsService: any ProjectsService
    let notesService: any NotesService
    let shareService: any ShareService
    let sharedService: any SharedService

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
                    projectsService: projectsService,
                    notesService: notesService,
                    shareService: shareService,
                    sharedService: sharedService,
                    invitationService: LocalInvitationService.makeForCurrentProcess(),
                    pendingInvitation: Binding(
                        get: { appState.pendingInvitation },
                        set: { newValue in
                            if newValue == nil {
                                appState.clearPendingInvitation()
                            }
                        }
                    )
                ) {
                    Task {
                        await appState.signOut(showSuccessToast: true)
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
