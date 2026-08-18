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
    @State private var projectsService: any ProjectsService
    @State private var notesService: MockNotesService
    @State private var shareService: MockShareService
    @State private var sharedService: any SharedService
    private let scanDetailService: (any ScanDetailService)?

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
        self.scanDetailService = isUITesting
            ? nil
            : ScanDetailRemoteService(httpClient: authenticatedClient)

        let resolvedProjectsService: any ProjectsService = isUITesting
            ? MockProjectsService.makeForCurrentProcess()
            : RemoteProjectsService(
                httpClient: authenticatedClient,
                localStore: LocalProjectsService(seedIfEmpty: false)
            )

        _appState = State(initialValue: appState)
        _projectsService = State(initialValue: resolvedProjectsService)
        _notesService = State(initialValue: MockNotesService())
        _shareService = State(initialValue: MockShareService.makeForCurrentProcess())
        _sharedService = State(initialValue: isUITesting
            ? MockSharedService.makeForCurrentProcess()
            : RemoteSharedService(httpClient: authenticatedClient)
        )
    }

    var body: some Scene {
        WindowGroup {
            AppView(
                appState: appState,
                projectsService: projectsService,
                scanDetailService: scanDetailService,
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
