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
    @State private var projectsViewModel: ProjectsViewModel
    @State private var sharedViewModel: SharedWithMeViewModel
    @State private var showsNewProject = false
    @State private var pendingCreatedProject: ProjectSummary?
    @State private var selectedCreatedProject: ProjectSummary?
    @State private var projectToEditAfterCreation: ProjectSummary?
    @State private var projectPendingDeleteAfterCreation: ProjectSummary?
    // Separate from ProjectsView's pending scan state: this request originates
    // from the project-creation cover and is published when HomeView's cover dismisses.
    @State private var scanRequestAfterProjectCreation: String?
    @State private var requestedScanSourceProjectID: String?
    @State private var isShowingProjectsDetail = false
    @State private var activeInvitation: PendingInvitation?
    @State private var isInvitationCoverPresented = false
    @State private var pendingAcceptedDestination: AcceptedInvitationDestination?
    @State private var acceptedProject: ProjectSummary?
    @State private var acceptedViewerInput: ViewerInput?
    @State private var acceptedInvitations = AcceptedInvitationCollection()
    @State private var feedbackToastMessage: String?
    @State private var feedbackToastDismissTask: Task<Void, Never>?

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
            onDismiss: publishPendingProjectScanRequest,
            content: { project in
                createdProjectDetailCover(for: project)
            }
        )
        .fullScreenCover(item: $projectToEditAfterCreation) { project in
            editCreatedProjectCover(for: project)
        }
        .alert(
            String(localized: "projects.delete.title"),
            isPresented: Binding(
                get: { projectPendingDeleteAfterCreation != nil },
                set: { if !$0 { projectPendingDeleteAfterCreation = nil } }
            ),
            presenting: projectPendingDeleteAfterCreation
        ) { project in
            Button(String(localized: "projects.delete.cancel"), role: .cancel) {
                projectPendingDeleteAfterCreation = nil
            }
            Button(String(localized: "projects.delete.confirm"), role: .destructive) {
                let projectID = project.id
                projectPendingDeleteAfterCreation = nil
                Task {
                    await projectsViewModel.deleteProject(id: projectID)
                }
            }
        } message: { project in
            Text(
                String.localizedStringWithFormat(
                    String(localized: "projects.delete.message.format"),
                    max(project.scanCount, project.roomScans.count),
                    project.name
                )
            )
        }
        .fullScreenCover(
            item: $activeInvitation,
            onDismiss: handleInvitationCoverDismissed
        ) { invitation in
            InvitationView(
                viewModel: InvitationViewModel(
                    pendingInvitation: invitation,
                    service: invitationService,
                    currentUserEmail: session.user.email
                ),
                onFinished: { outcome in
                    handleInvitationFinished(outcome, for: invitation)
                }
            )
            .onDisappear {
                handleInvitationDismissed(invitation)
            }
        }
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
            activeInvitation = invitation
            isInvitationCoverPresented = true
        }
        .onAppear {
            if let pendingInvitation {
                activeInvitation = pendingInvitation
                isInvitationCoverPresented = true
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    @ViewBuilder
    private var currentTabContent: some View {
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
    func handleInvitationFinished(
        _ outcome: InvitationViewModel.NavigationOutcome,
        for invitation: PendingInvitation
    ) {
        guard activeInvitation?.id == invitation.id else { return }
        activeInvitation = nil
        clearPendingInvitation(matching: invitation)

        switch outcome {
        case .dismissedToHome(let toastMessage):
            if !toastMessage.isEmpty { feedbackToastMessage = toastMessage }
        case .accepted(let destination, let toastMessage):
            acceptedInvitations.store(destination)
            feedbackToastMessage = toastMessage
            Task {
                await sharedViewModel.ingestAcceptedDestination(destination)
                Task { await sharedViewModel.refreshAllContent() }
                await presentAcceptedDestinationWhenReady(destination)
            }
        case .opened(let destination): Task { await presentAcceptedDestinationWhenReady(destination) }
        }
    }

    func handleInvitationDismissed(_ invitation: PendingInvitation) {
        // Ignore transient teardown while this invite is still the presented item.
        // If a newer invite replaced it, pendingInvitation has a different id and is left alone.
        guard activeInvitation?.id != invitation.id else { return }
        clearPendingInvitation(matching: invitation)
    }

    func handleInvitationCoverDismissed() {
        isInvitationCoverPresented = false
        guard let destination = pendingAcceptedDestination else { return }
        pendingAcceptedDestination = nil
        Task { await openAcceptedDestination(destination) }
    }

    func clearPendingInvitation(matching invitation: PendingInvitation) {
        guard pendingInvitation?.id == invitation.id else { return }
        pendingInvitation = nil
    }

    func presentAcceptedDestinationWhenReady(_ destination: AcceptedInvitationDestination) async {
        guard !isInvitationCoverPresented else {
            pendingAcceptedDestination = destination
            return
        }
        await openAcceptedDestination(destination)
    }

    func openAcceptedDestination(_ destination: AcceptedInvitationDestination) async {
        switch destination {
        case .project(let project):
            acceptedProject = project
        case .scan(let item):
            guard let scanDetailService else {
                acceptedViewerInput = item.viewerInput
                return
            }

            do {
                let detail = try await scanDetailService.fetchScanDetail(id: item.id)
                acceptedViewerInput = ViewerInput(
                    projectID: item.projectID,
                    projectName: item.projectName,
                    scanID: item.id,
                    scanName: detail.name,
                    modelVersion: String(detail.modelVersion),
                    modelURL: item.detailScan?.localModelURL,
                    syncStatus: detail.syncStatus,
                    assetStatus: detail.assetStatus
                )
            } catch {
                acceptedViewerInput = item.viewerInput
            }
        }
    }

    func applyAcceptedProjectScanUpdate(projectID: ProjectSummary.ID, scan: RoomScanSummary) {
        acceptedInvitations.applyUpdatedScan(projectID: projectID, scan: scan)
        projectsViewModel.applyUpdatedScan(projectID: projectID, scan: scan)
    }

    func applyAcceptedProjectScanDeletion(projectID: ProjectSummary.ID, scanID: RoomScanSummary.ID) {
        acceptedInvitations.applyDeletedScan(projectID: projectID, scanID: scanID)
        projectsViewModel.applyDeletedScan(projectID: projectID, scanID: scanID)
    }
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
                projectToEditAfterCreation = project
            },
            onDelete: { project in
                projectPendingDeleteAfterCreation = project
            }
        )
    }

    func editCreatedProjectCover(for project: ProjectSummary) -> some View {
        NewProjectView(
            mode: .edit,
            initialName: project.name,
            initialDescription: project.description,
            onSave: { form in
                let didUpdate = await projectsViewModel.updateProject(
                    id: project.id,
                    name: form.name,
                    description: form.projectDescription,
                    revision: project.revision
                )
                if didUpdate {
                    projectToEditAfterCreation = nil
                }
                return didUpdate
            },
            onCancel: {
                projectToEditAfterCreation = nil
                projectsViewModel.dismissActionErrorToast()
            }
        )
        .alert(
            String(localized: "projects.action.error"),
            isPresented: Binding(
                get: { projectsViewModel.showsActionErrorToast },
                set: { if !$0 { projectsViewModel.dismissActionErrorToast() } }
            )
        ) {
            Button(String(localized: "projects.action.error.dismiss"), role: .cancel) {
                projectsViewModel.dismissActionErrorToast()
            }
        }
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
