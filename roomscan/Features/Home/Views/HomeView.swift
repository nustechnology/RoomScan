//
//  HomeView.swift
//  roomscan
//

import SwiftUI

struct HomeView: View {
    enum Tab {
        case projects
        case share
        case account
    }

    let session: AuthenticationSession
    let projectsService: any ProjectsService
    let sharedService: any SharedService
    let invitationService: any InvitationService
    @Binding var pendingInvitation: PendingInvitation?
    let onSignOut: () -> Void

    @State private var selectedTab: Tab = .projects
    @State private var projectsViewModel: ProjectsViewModel
    @State private var shareHomeViewModel: ShareHomeViewModel
    @State private var showsNewProject = false
    @State private var pendingCreatedProject: ProjectSummary?
    @State private var selectedCreatedProject: ProjectSummary?
    @State private var isShowingProjectsDetail = false
    @State private var activeInvitation: PendingInvitation?
    @State private var acceptedProject: ProjectSummary?
    @State private var acceptedViewerInput: ViewerInput?
    @State private var acceptedInvitations = AcceptedInvitationCollection()
    @State private var feedbackToastMessage: String?

    init(
        session: AuthenticationSession,
        projectsService: any ProjectsService,
        sharedService: any SharedService,
        invitationService: any InvitationService,
        pendingInvitation: Binding<PendingInvitation?> = .constant(nil),
        onSignOut: @escaping () -> Void
    ) {
        self.session = session
        self.projectsService = projectsService
        self.sharedService = sharedService
        self.invitationService = invitationService
        _pendingInvitation = pendingInvitation
        self.onSignOut = onSignOut
        _projectsViewModel = State(
            initialValue: ProjectsViewModel(service: projectsService)
        )
        _shareHomeViewModel = State(
            initialValue: ShareHomeViewModel(service: sharedService)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isShowingProjectsDetail {
                HomeHeader(
                    title: selectedTab.headerTitle,
                    showsCreateProjectButton: selectedTab == .projects,
                    trailingStyle: selectedTab == .share ? .refresh : .settings,
                    onCreateProject: {
                        showsNewProject = true
                    },
                    onRefresh: {
                        Task {
                            await shareHomeViewModel.refresh()
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
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                feedbackToastMessage = nil
            }
        }
        .fullScreenCover(isPresented: $showsNewProject, onDismiss: {
            selectedCreatedProject = pendingCreatedProject
            pendingCreatedProject = nil
        }, content: {
            NewProjectView(
                onSave: { name, _ in
                    let createdProject = makeCreatedProject(named: name)
                    pendingCreatedProject = createdProject
                    showsNewProject = false
                },
                onCancel: {
                    showsNewProject = false
                }
            )
        })
        .fullScreenCover(item: $selectedCreatedProject) { project in
            ProjectDetailView(
                project: project,
                projectsService: projectsService,
                currentUserID: session.user.id,
                onScanUpdated: { updatedScan in
                    projectsViewModel.applyUpdatedScan(projectID: project.id, scan: updatedScan)
                },
                onScanDeleted: { scanID in
                    projectsViewModel.applyDeletedScan(projectID: project.id, scanID: scanID)
                }
            )
        }
        .fullScreenCover(
            item: $activeInvitation,
            onDismiss: {
                pendingInvitation = nil
            },
            content: { invitation in
                InvitationView(
                    viewModel: InvitationViewModel(
                        pendingInvitation: invitation,
                        service: invitationService,
                        currentUserEmail: session.user.email
                    ),
                    onFinished: handleInvitationFinished
                )
            }
        )
        .fullScreenCover(item: $acceptedProject) { project in
            ProjectDetailView(
                project: project,
                projectsService: projectsService,
                currentUserID: session.user.id,
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
                notesService: MockNotesService.shared,
                onBack: { acceptedViewerInput = nil },
                onScanRenamed: { newName in
                    acceptedInvitations.applyRenamedScan(scanID: input.scanID, name: newName)
                }
            )
        }
        .onChange(of: pendingInvitation) { _, invitation in
            guard let invitation else { return }
            activeInvitation = invitation
        }
        .onAppear {
            if let pendingInvitation {
                activeInvitation = pendingInvitation
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
                currentUserID: session.user.id,
                showsNavigationTitle: false,
                isShowingDetail: $isShowingProjectsDetail
            )
        case .share:
            ShareHomeView(
                viewModel: shareHomeViewModel,
                acceptedDestinations: acceptedInvitations.destinations,
                onOpen: openAcceptedDestination
            )
        case .account:
            AccountHomeView(session: session, onSignOut: onSignOut)
        }
    }

    private func handleInvitationFinished(_ outcome: InvitationViewModel.NavigationOutcome) {
        activeInvitation = nil
        pendingInvitation = nil

        switch outcome {
        case .dismissedToHome(let toastMessage):
            if !toastMessage.isEmpty {
                feedbackToastMessage = toastMessage
            }
        case .accepted(let destination, let toastMessage):
            acceptedInvitations.store(destination)
            feedbackToastMessage = toastMessage
            openAcceptedDestination(destination)
        }
    }

    private func openAcceptedDestination(_ destination: AcceptedInvitationDestination) {
        switch destination {
        case .project(let project):
            acceptedProject = project
        case .scan(let input):
            acceptedViewerInput = input
        }
    }

    private func applyAcceptedProjectScanUpdate(projectID: ProjectSummary.ID, scan: RoomScanSummary) {
        acceptedInvitations.applyUpdatedScan(projectID: projectID, scan: scan)
        projectsViewModel.applyUpdatedScan(projectID: projectID, scan: scan)
    }

    private func applyAcceptedProjectScanDeletion(projectID: ProjectSummary.ID, scanID: RoomScanSummary.ID) {
        acceptedInvitations.applyDeletedScan(projectID: projectID, scanID: scanID)
        projectsViewModel.applyDeletedScan(projectID: projectID, scanID: scanID)
    }

    private func makeCreatedProject(named name: String) -> ProjectSummary {
        ProjectSummary(
            id: "created-project-\(UUID().uuidString)",
            name: name,
            ownerName: "You",
            createdAt: Date(),
            updatedAt: Date(),
            description: "",
            sharedUserCount: 0,
            roomScans: []
        )
    }
}

private struct HomeBottomNav: View {
    @Binding var selectedTab: HomeView.Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HomeView.Tab.allCases, id: \.self) { tab in
                Button(
                    action: {
                        selectedTab = tab
                    },
                    label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.systemImageName(isSelected: selectedTab == tab))
                                .font(.system(size: 21, weight: .semibold))

                            Text(tab.localizedTitle)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(selectedTab == tab ? AppColors.brandBlueBottom : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .contentShape(Rectangle())
                    }
                )
                .buttonStyle(.plain)
                .accessibilityLabel(tab.localizedTitle)
                .accessibilityIdentifier(tab.accessibilityIdentifier)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.quaternary)
                .frame(height: 1)
        }
    }
}

extension HomeView.Tab: CaseIterable {
    var headerTitle: String {
        switch self {
        case .projects:
            return String(localized: "projects.title")
        case .share:
            return String(localized: "home.share.headerTitle")
        case .account:
            return String(localized: "account.title")
        }
    }

    var localizedTitle: String {
        switch self {
        case .projects:
            return String(localized: "projects.nav.project")
        case .share:
            return String(localized: "home.share.nav")
        case .account:
            return String(localized: "account.title")
        }
    }

    func systemImageName(isSelected: Bool) -> String {
        switch self {
        case .projects:
            return isSelected ? "square.grid.2x2.fill" : "square.grid.2x2"
        case .share:
            return "point.3.filled.connected.trianglepath.dotted"
        case .account:
            return isSelected ? "person.fill" : "person"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .projects:
            return "tab.projects"
        case .share:
            return "tab.share"
        case .account:
            return "tab.account"
        }
    }
}

private struct HomeHeader: View {
    enum TrailingStyle {
        case settings
        case refresh
    }

    let title: String
    let showsCreateProjectButton: Bool
    var trailingStyle: TrailingStyle = .settings
    let onCreateProject: () -> Void
    var onRefresh: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.largeTitle.bold())
                .lineLimit(1)
                .accessibilityIdentifier("home.header.title")

            if showsCreateProjectButton {
                Button(action: onCreateProject) {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "projects.create.accessibility"))
                .accessibilityIdentifier("projects.create")
            }

            Spacer()

            switch trailingStyle {
            case .settings:
                Button(
                    action: {},
                    label: {
                        Image(systemName: "gearshape")
                            .frame(width: 44, height: 44)
                    }
                )
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "home.settings.accessibility"))
                .accessibilityIdentifier("home.settings")

            case .refresh:
                Button(
                    action: { onRefresh?() },
                    label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                )
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "shared.refresh.accessibility"))
                .accessibilityIdentifier("shared.refresh")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 2)
        .padding(.bottom, 4)
        .background(.background)
    }
}

private struct AccountHomeView: View {
    let session: AuthenticationSession
    let onSignOut: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(session.user.displayName ?? String(localized: "account.defaultName"))
                .font(.title3.bold())
                .lineLimit(1)
                .accessibilityIdentifier("account.displayName")

            if let email = session.user.email {
                Text(email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("account.email")
            }

            Button(String(localized: "account.signOut"), action: onSignOut)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("account.signOut")
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    HomeView(
        session: .mockAppleUser,
        projectsService: MockProjectsService(simulatedDelayNanoseconds: 0),
        sharedService: MockSharedService(simulatedDelayNanoseconds: 0),
        invitationService: LocalInvitationService(simulatedDelayNanoseconds: 0),
        onSignOut: {}
    )
}
