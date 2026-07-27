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
    let onSignOut: () -> Void

    @State private var selectedTab: Tab = .projects
    @State private var projectsViewModel: ProjectsViewModel
    @State private var showsNewProject = false
    @State private var pendingCreatedProject: ProjectSummary?
    @State private var selectedCreatedProject: ProjectSummary?

    init(
        session: AuthenticationSession,
        projectsService: any ProjectsService,
        onSignOut: @escaping () -> Void
    ) {
        self.session = session
        self.projectsService = projectsService
        self.onSignOut = onSignOut
        _projectsViewModel = State(
            initialValue: ProjectsViewModel(service: projectsService)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HomeHeader(
                title: selectedTab.headerTitle,
                showsCreateProjectButton: selectedTab == .projects,
                onCreateProject: {
                    showsNewProject = true
                }
            )

            currentTabContent
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HomeBottomNav(selectedTab: $selectedTab)
        }
        .fullScreenCover(isPresented: $showsNewProject, onDismiss: {
            selectedCreatedProject = pendingCreatedProject
            pendingCreatedProject = nil
        }) {
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
        }
        .fullScreenCover(item: $selectedCreatedProject) { project in
            ProjectDetailView(project: project)
        }
    }

    @ViewBuilder
    private var currentTabContent: some View {
        switch selectedTab {
        case .projects:
            ProjectsView(
                viewModel: projectsViewModel,
                showsNavigationTitle: false
            )
        case .share:
            ShareHomeView()
        case .account:
            AccountHomeView(session: session, onSignOut: onSignOut)
        }
    }

    private func makeCreatedProject(named name: String) -> ProjectSummary {
        ProjectSummary(
            id: "created-project-\(UUID().uuidString)",
            name: name,
            ownerName: "You",
            createdAt: Date(),
            updatedAt: Date(),
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
                        .foregroundStyle(selectedTab == tab ? .blue : .secondary)
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
            return String(localized: "home.share.title")
        case .account:
            return String(localized: "account.title")
        }
    }

    var localizedTitle: String {
        switch self {
        case .projects:
            return String(localized: "projects.nav.project")
        case .share:
            return String(localized: "home.share.title")
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
    let title: String
    let showsCreateProjectButton: Bool
    let onCreateProject: () -> Void

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
        }
        .padding(.horizontal, 24)
        .padding(.top, 2)
        .padding(.bottom, 4)
        .background(.background)
    }
}

private struct ShareHomeView: View {
    var body: some View {
        ContentUnavailableView(
            String(localized: "home.share.title"),
            systemImage: "square.and.arrow.up",
            description: Text("home.share.placeholder")
        )
        .accessibilityIdentifier("home.share")
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
        onSignOut: {}
    )
}
