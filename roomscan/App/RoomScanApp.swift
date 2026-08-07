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
    @State private var projectsService: MockProjectsService
    @State private var notesService: MockNotesService
    @State private var shareService: MockShareService
    @State private var sharedService: MockSharedService

    private let authenticatedHTTPClient: any HTTPClient

    init() {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-UITesting")
        let httpClient = LiveHTTPClient()
        let keychainStore = LiveKeychainTokenStore()
        let refreshCoordinator = AccessTokenRefreshCoordinator(
            httpClient: httpClient,
            keychainStore: keychainStore
        )

        let authenticationService: any AuthenticationService = isUITesting
            ? MockAuthenticationService.makeForCurrentProcess()
            : RemoteAuthenticationService(
                httpClient: httpClient,
                keychainStore: keychainStore,
                refreshCoordinator: refreshCoordinator
            )
        let appState = AppState(authenticationService: authenticationService)
        let authenticatedClient = AuthenticatedHTTPClient(
            httpClient: httpClient,
            keychainStore: keychainStore,
            refreshCoordinator: refreshCoordinator
        ) {
            appState.handleSessionInvalidated()
        }

        self.authenticatedHTTPClient = authenticatedClient

        _appState = State(initialValue: appState)
        _projectsService = State(initialValue: MockProjectsService.makeForCurrentProcess())
        _notesService = State(initialValue: MockNotesService())
        _shareService = State(initialValue: MockShareService.makeForCurrentProcess())
        _sharedService = State(initialValue: MockSharedService.makeForCurrentProcess())
    }

    var body: some Scene {
        WindowGroup {
            AppView(
                appState: appState,
                projectsService: projectsService,
                notesService: notesService,
                shareService: shareService,
                sharedService: sharedService
            )
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
