//
//  HomeView.swift
//  roomscan
//

import SwiftUI

struct HomeView: View {
    enum Tab: CaseIterable {
        case projects
        case share
        case account
    }

    let session: AuthenticationSession
    let projectsService: any ProjectsService
    let scanDetailService: (any ScanDetailService)?
    let notesService: any NotesService
    let shareService: any ShareService
    let sharedService: any SharedService
    let syncService: any SyncService
    let usersService: any UsersService
    let syncEngine: SyncEngine?
    let invitationService: any InvitationService
    @Binding var pendingInvitation: PendingInvitation?
    let onUserUpdated: (AuthenticatedUser) -> Void
    let onSignOut: () -> Void

    @State private var selectedTab: Tab = .projects
    // Not `private`: also mutated from HomeView+InvitationOverlay.swift.
    @State var projectsViewModel: ProjectsViewModel
    @State var sharedViewModel: SharedWithMeViewModel
    @State private var showsNewProject = false
    @State private var pendingCreatedProject: ProjectSummary?
    @State private var selectedCreatedProject: ProjectSummary?
    @State private var ownerActionHandoff: CreatedProjectOwnerActionController
    // Separate from ProjectsView's pending scan state: this request originates
    // from the project-creation cover and is published when HomeView's cover dismisses.
    @State private var scanRequestAfterProjectCreation: String?
    @State private var requestedScanSourceProjectID: String?
    @State private var isShowingProjectsDetail = false
    // The following are also mutated from HomeView+InvitationOverlay.swift, so cannot
    // be `private` (which is scoped to this file's declarations only).
    @State var invitationOverlayPresenter: InvitationOverlayWindowPresenter
    @State var acceptedProject: ProjectSummary?
    @State var acceptedViewerInput: ViewerInput?
    @State var pendingAcceptedDestination: AcceptedInvitationDestination?
    @State var acceptedInvitations = AcceptedInvitationCollection()
    @State var feedbackToastMessage: String?
    @State private var feedbackToastDismissTask: Task<Void, Never>?
    @State var invitationOverlayRetryTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    init(
        session: AuthenticationSession,
        projectsService: any ProjectsService,
        scanDetailService: (any ScanDetailService)? = nil,
        notesService: any NotesService,
        shareService: any ShareService,
        sharedService: any SharedService,
        syncService: any SyncService,
        usersService: any UsersService,
        syncEngine: SyncEngine? = nil,
        invitationService: any InvitationService,
        overlayPresenter: InvitationOverlayWindowPresenter? = nil,
        pendingInvitation: Binding<PendingInvitation?> = .constant(nil),
        onUserUpdated: @escaping (AuthenticatedUser) -> Void = { _ in },
        onSignOut: @escaping () -> Void
    ) {
        self.session = session
        self.projectsService = projectsService
        self.scanDetailService = scanDetailService
        self.notesService = notesService
        self.shareService = shareService
        self.sharedService = sharedService
        self.syncService = syncService
        self.usersService = usersService
        self.syncEngine = syncEngine
        self.invitationService = invitationService
        _invitationOverlayPresenter = State(
            initialValue: overlayPresenter ?? InvitationOverlayWindowPresenter()
        )
        _pendingInvitation = pendingInvitation
        self.onUserUpdated = onUserUpdated
        self.onSignOut = onSignOut
        _projectsViewModel = State(
            initialValue: ProjectsViewModel(
                service: projectsService,
                syncEngine: syncEngine,
                currentUserID: session.user.id
            )
        )
        _sharedViewModel = State(
            initialValue: SharedWithMeViewModel(
                service: sharedService,
                syncEngine: syncEngine,
                currentUserID: session.user.id
            )
        )
        _ownerActionHandoff = State(initialValue: CreatedProjectOwnerActionController())
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isShowingProjectsDetail {
                HomeHeader(
                    title: selectedTab.headerTitle,
                    showsCreateProjectButton: selectedTab == .projects,
                    showsRefreshButton: selectedTab == .share,
                    onCreateProject: {
                        showsNewProject = true
                    },
                    onRefresh: {
                        Task {
                            await sharedViewModel.refreshSelectedTab()
                        }
                    }
                )
            }

            currentTabContent
                .padding(.top, isShowingProjectsDetail ? 0 : 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !isShowingProjectsDetail {
                HomeBottomNav(selectedTab: $selectedTab)
            }
        }
        .overlay {
            projectDeleteLoadingOverlay
        }
        .overlay(alignment: .bottom) {
            if let feedbackToastMessage {
                Text(feedbackToastMessage)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.88))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityIdentifier("invitation.toast")
            }
        }
        .animation(.default, value: feedbackToastMessage)
        .onChange(of: feedbackToastMessage) { _, message in
            guard message != nil else { return }
            feedbackToastDismissTask?.cancel()
            feedbackToastDismissTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 2_500_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                feedbackToastMessage = nil
            }
        }
        .fullScreenCover(
            isPresented: $showsNewProject,
            onDismiss: {
                selectedCreatedProject = pendingCreatedProject
                pendingCreatedProject = nil
            },
            content: {
                NewProjectView(
                    onSave: { form in
                        await saveNewProject(form)
                    },
                    onCancel: {
                        showsNewProject = false
                    }
                )
            }
        )
        .fullScreenCover(
            item: $selectedCreatedProject,
            onDismiss: {
                ownerActionHandoff.presentAfterDetailDismiss()
                publishPendingProjectScanRequest()
            },
            content: { project in
                createdProjectDetailCover(for: project)
            }
        )
        .projectOwnerActionPresentation(
            projectToEdit: $ownerActionHandoff.activeEdit,
            projectPendingDelete: $ownerActionHandoff.activeDelete,
            projectsViewModel: projectsViewModel,
            onEditAppeared: { ownerActionHandoff.acknowledgeEditAppeared($0) },
            onDeleteDismissed: { ownerActionHandoff.acknowledgeDeleteDismissed() }
        )
        .fullScreenCover(item: $acceptedProject) { project in
            ProjectDetailView(
                project: project,
                projectsService: projectsService,
                scanDetailService: scanDetailService,
                notesService: notesService,
                shareService: shareService,
                syncEngine: syncEngine,
                currentUserID: session.user.id,
                accessPolicy: .readOnly,
                onScanUpdated: { updatedScan in
                    applyAcceptedProjectScanUpdate(projectID: project.id, scan: updatedScan)
                },
                onScanDeleted: { scanID in
                    applyAcceptedProjectScanDeletion(projectID: project.id, scanID: scanID)
                }
            )
        }
        .fullScreenCover(item: $acceptedViewerInput) { input in
            ViewerView(
                input: input,
                notesService: notesService,
                modelDownloadService: scanDetailService,
                accessPolicy: .readOnly,
                shareService: shareService,
                onBack: { acceptedViewerInput = nil },
                onScanRenamed: { updatedDetail in
                    acceptedInvitations.applyRenamedScan(scanID: input.scanID, name: updatedDetail.name)
                }
            )
        }
        .onChange(of: pendingInvitation) { _, invitation in
            guard let invitation else { return }
            presentInvitationOverlay(invitation)
        }
        .onAppear {
            if let pendingInvitation {
                presentInvitationOverlay(pendingInvitation)
            }
            flushPendingAcceptedDestinationIfReady()
        }
        .onChange(of: scenePhase) { _, phase in
            // A failed presentation is most often caused by no foreground-active
            // `UIWindowScene` existing yet (app launch, scene handoff, backgrounding).
            // Becoming active is exactly the moment that resolves, so re-attempt then
            // rather than relying on `onAppear`, which won't fire again while HomeView
            // stays on screen.
            guard phase == .active, let pendingInvitation, !invitationOverlayPresenter.isPresented else { return }
            presentInvitationOverlay(pendingInvitation)
        }
        .onDisappear {
            invitationOverlayRetryTask?.cancel()
            invitationOverlayRetryTask = nil
            invitationOverlayPresenter.dismissWithoutNotifying()
        }
        .onChange(of: selectedTab) { _, _ in
            // Avoid presenting a delayed edit/delete cover over a different tab.
            ownerActionHandoff.cancelUnacknowledgedPresentation()
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

}

private extension HomeView {
    @ViewBuilder
    var currentTabContent: some View {
        switch selectedTab {
        case .projects:
            ProjectsView(
                viewModel: projectsViewModel,
                projectsService: projectsService,
                scanDetailService: scanDetailService,
                notesService: notesService,
                shareService: shareService,
                syncEngine: syncEngine,
                currentUserID: session.user.id,
                showsNavigationTitle: false,
                isShowingDetail: $isShowingProjectsDetail,
                requestedScanSourceProjectID: $requestedScanSourceProjectID
            )
        case .share:
            SharedWithMeView(
                viewModel: sharedViewModel,
                projectsService: projectsService,
                scanDetailService: scanDetailService,
                notesService: notesService,
                shareService: shareService,
                syncEngine: syncEngine,
                currentUserID: session.user.id
            )
        case .account:
            AccountView(
                session: session,
                projectsService: projectsService,
                sharedService: sharedService,
                syncService: syncService,
                usersService: usersService,
                storageMeasuring: RealAccountStorageMeasuring(),
                onUserUpdated: onUserUpdated,
                onSignOut: onSignOut
            )
        }
    }

}

private extension HomeView {
    func saveNewProject(_ form: ProjectFormInput) async -> Bool {
        let name = form.name
        let projectDescription = form.projectDescription
        do {
            let createdProject = try await projectsService.createProject(
                name: name,
                projectDescription: projectDescription
            )
            projectsViewModel.prependCreatedProject(createdProject)
            pendingCreatedProject = createdProject
            showsNewProject = false
            return true
        } catch {
            #if DEBUG
            print("saveNewProject failed: \(error)")
            #endif
            return false
        }
    }
    func publishPendingProjectScanRequest() {
        guard let scanRequestAfterProjectCreation else { return }
        requestedScanSourceProjectID = scanRequestAfterProjectCreation
        self.scanRequestAfterProjectCreation = nil
    }

    func createdProjectDetailCover(for project: ProjectSummary) -> some View {
        ProjectDetailView(
            project: project,
            projectsService: projectsService,
            scanDetailService: scanDetailService,
            notesService: notesService,
            shareService: shareService,
            syncEngine: syncEngine,
            currentUserID: session.user.id,
            onScanUpdated: { updatedScan in
                projectsViewModel.applyUpdatedScan(projectID: project.id, scan: updatedScan)
            },
            onScanDeleted: { scanID in
                projectsViewModel.applyDeletedScan(projectID: project.id, scanID: scanID)
            },
            onAddScan: { projectID in
                scanRequestAfterProjectCreation = projectID
                selectedCreatedProject = nil
            },
            onEdit: { project in
                ownerActionHandoff.begin(
                    .edit(project),
                    detailIsPresented: selectedCreatedProject != nil
                ) {
                    selectedCreatedProject = nil
                }
            },
            onDelete: { project in
                ownerActionHandoff.begin(
                    .delete(project),
                    detailIsPresented: selectedCreatedProject != nil
                ) {
                    selectedCreatedProject = nil
                }
            }
        )
    }

    /// Covers Home header, tab content, and bottom nav while a project delete is in flight.
    var projectDeleteLoadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            ProgressView(String(localized: "projects.delete.loading"))
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .opacity(projectsViewModel.isDeletingProject ? 1 : 0)
        .allowsHitTesting(projectsViewModel.isDeletingProject)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(projectsViewModel.isDeletingProject ? .isModal : [])
        .accessibilityHidden(!projectsViewModel.isDeletingProject)
        .accessibilityIdentifier("projects.delete.loading")
    }
}

#Preview {
    HomeView(
        session: .mockAppleUser,
        projectsService: MockProjectsService(simulatedDelayNanoseconds: 0),
        notesService: MockNotesService(),
        shareService: MockShareService(simulatedDelayNanoseconds: 0),
        sharedService: MockSharedService(simulatedDelayNanoseconds: 0),
        syncService: MockSyncService(simulatedDelayNanoseconds: 0),
        usersService: MockUsersService(),
        invitationService: LocalInvitationService(simulatedDelayNanoseconds: 0),
        onSignOut: {}
    )
}
