//
//  roomscanApp.swift
//  roomscan
//

import Foundation
import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        return true
    }
}

@main
struct RoomScanApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var appState: AppState
    @State private var projectsService: any ProjectsService
    @State private var notesService: any NotesService
    @State private var shareService: any ShareService
    @State private var sharedService: any SharedService
    @State private var syncService: any SyncService
    @State private var usersService: any UsersService
    @State private var syncEngine: SyncEngine?
    @State private var invitationService: any InvitationService
    private let scanDetailService: (any ScanDetailService)?

    init() {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-UITesting")
        let httpClient = LiveHTTPClient()
        let keychainStore = LiveKeychainTokenStore()
        let refreshCoordinator = AccessTokenRefreshCoordinator(
            httpClient: httpClient,
            keychainStore: keychainStore
        )

        let (authenticationService, remoteAuthenticationService) = Self.makeAuthentication(
            isUITesting: isUITesting,
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

        let localProjectsStore = LocalProjectsService(seedIfEmpty: false)
        let resolvedSharedService: any SharedService = isUITesting
            ? MockSharedService.makeForCurrentProcess()
            : RemoteSharedService(httpClient: authenticatedClient)

        let resolvedProjectsService: any ProjectsService = isUITesting
            ? MockProjectsService.makeForCurrentProcess()
            : RemoteProjectsService(
                httpClient: authenticatedClient,
                localStore: localProjectsStore
            )

        let resolvedNotesService: any NotesService = isUITesting
            ? MockNotesService()
            : RemoteNotesService(httpClient: authenticatedClient)

        let resolvedShareService: any ShareService = isUITesting
            ? MockShareService.makeForCurrentProcess()
            : RemoteShareService(httpClient: authenticatedClient)

        let resolvedSyncService: any SyncService = isUITesting
            ? MockSyncService.makeForCurrentProcess()
            : RemoteSyncService(httpClient: authenticatedClient)

        let resolvedUsersService: any UsersService = isUITesting
            ? MockUsersService.makeForCurrentProcess()
            : RemoteUsersService(httpClient: authenticatedClient)
        remoteAuthenticationService?.attachUsersService(resolvedUsersService)

        let resolvedInvitationService: any InvitationService = isUITesting
            ? LocalInvitationService.makeForCurrentProcess()
            : RemoteInvitationService(httpClient: authenticatedClient)

        let resolvedSyncEngine: SyncEngine? = isUITesting
            ? nil
            : SyncEngine(
                syncService: resolvedSyncService,
                localCache: localProjectsStore,
                sharedService: resolvedSharedService
            )

        _appState = State(initialValue: appState)
        _projectsService = State(initialValue: resolvedProjectsService)
        _notesService = State(initialValue: resolvedNotesService)
        _shareService = State(initialValue: resolvedShareService)
        _sharedService = State(initialValue: resolvedSharedService)
        _syncService = State(initialValue: resolvedSyncService)
        _usersService = State(initialValue: resolvedUsersService)
        _syncEngine = State(initialValue: resolvedSyncEngine)
        _invitationService = State(initialValue: resolvedInvitationService)
    }

    var body: some Scene {
        WindowGroup {
            AppView(
                appState: appState,
                projectsService: projectsService,
                scanDetailService: scanDetailService,
                notesService: notesService,
                shareService: shareService,
                sharedService: sharedService,
                syncService: syncService,
                usersService: usersService,
                syncEngine: syncEngine,
                invitationService: invitationService
            )
                .task {
                    await appState.restoreSession()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        appState.recordActivity()
                        if case .authenticated(let session) = appState.phase {
                            Task {
                                try? await syncEngine?.pullChanges(forUserId: session.user.id)
                            }
                        }
                    }
                }
                .onChange(of: appState.phase) { oldPhase, newPhase in
                    if case .authenticated(let session) = oldPhase, case .signedOut = newPhase {
                        Task {
                            await syncEngine?.clearCursor(forUserId: session.user.id)
                        }
                    }
                }
                .onOpenURL { url in
                    appState.handleIncomingURL(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    appState.handleIncomingURL(url)
                }
        }
    }

    private static func makeAuthentication(
        isUITesting: Bool,
        httpClient: any HTTPClient,
        keychainStore: any KeychainTokenStore,
        refreshCoordinator: AccessTokenRefreshCoordinator
    ) -> (any AuthenticationService, RemoteAuthenticationService?) {
        if isUITesting {
            return (MockAuthenticationService.makeForCurrentProcess(), nil)
        }

        let remote = RemoteAuthenticationService(
            httpClient: httpClient,
            keychainStore: keychainStore,
            refreshCoordinator: refreshCoordinator
        )
        return (remote, remote)
    }
}
