//
//  ProjectsView.swift
//  roomscan
//

import SwiftUI

struct ProjectsView: View {
    @State var viewModel: ProjectsViewModel
    @State private var selectedProject: ProjectSummary?
    @State private var selectedScanDetail: ScanDetailDestination?
    @State private var shareInput: ShareScreenInput?
    let projectsService: any ProjectsService
    let notesService: any NotesService
    let shareService: any ShareService
    var currentUserID: String
    var showsNavigationTitle = true
    @Binding var isShowingDetail: Bool

    @State private var showsScanCheck = false
    @State private var projectToEdit: ProjectSummary?
    @State private var projectPendingDelete: ProjectSummary?
    @FocusState private var isSearchFocused: Bool

    init(
        viewModel: ProjectsViewModel,
        projectsService: any ProjectsService,
        notesService: any NotesService,
        shareService: any ShareService,
        currentUserID: String,
        showsNavigationTitle: Bool = true,
        isShowingDetail: Binding<Bool> = .constant(false)
    ) {
        _viewModel = State(initialValue: viewModel)
        self.projectsService = projectsService
        self.notesService = notesService
        self.shareService = shareService
        self.currentUserID = currentUserID
        self.showsNavigationTitle = showsNavigationTitle
        _isShowingDetail = isShowingDetail
    }

    var body: some View {
        NavigationStack {
            rootContent
        }
    }

    private var rootContent: some View {
        toastOverlay
            .navigationTitle(showsNavigationTitle ? String(localized: "projects.title") : "")
            .toolbar(showsNavigationTitle ? .visible : .hidden, for: .navigationBar)
            .modifier(ProjectsPresentationModifier(
                selectedProject: $selectedProject,
                selectedScanDetail: $selectedScanDetail,
                shareInput: $shareInput,
                showsScanCheck: $showsScanCheck,
                projectToEdit: $projectToEdit,
                projectPendingDelete: $projectPendingDelete,
                isShowingDetail: $isShowingDetail,
                viewModel: viewModel,
                projectsService: projectsService,
                notesService: notesService,
                shareService: shareService,
                currentUserID: currentUserID
            ))
    }

    private var toastOverlay: some View {
        ZStack(alignment: .bottom) {
            content
            toastViews
        }
        .animation(.default, value: viewModel.showsPaginationError)
        .animation(.default, value: viewModel.showsDeleteSuccessToast)
        .animation(.default, value: viewModel.showsActionErrorToast)
    }

    @ViewBuilder
    private var toastViews: some View {
        if viewModel.showsPaginationError {
            PaginationErrorToast {
                Task {
                    await viewModel.retryPagination()
                }
            }
            .padding()
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        if viewModel.showsDeleteSuccessToast {
            DeleteSuccessToast()
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        if viewModel.showsActionErrorToast && projectToEdit == nil {
            ActionErrorToast()
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.viewState {
        case .idle, .loading:
            ProgressView(String(localized: "projects.loading"))
                .accessibilityIdentifier("projects.loading")

        case .empty:
            ContentUnavailableView(String(localized: "projects.empty.message"), systemImage: "folder")
                .accessibilityIdentifier("projects.emptyState")

        case .failed:
            ContentUnavailableView(String(localized: "projects.load.error"), systemImage: "wifi.exclamationmark")
                .accessibilityIdentifier("projects.loadError")

        case .loaded:
            ScrollView {
                LazyVStack(spacing: 14) {
                    if viewModel.isRefreshing {
                        RefreshingBannerView()
                    }

                    SearchBarView(
                        searchQuery: Binding(
                            get: { viewModel.searchQuery },
                            set: { query in
                                viewModel.updateSearchQuery(query)
                            }
                        ),
                        isSearchFocused: $isSearchFocused
                    )
                    ProjectsContentSection(
                        viewModel: viewModel,
                        onNewScan: { showsScanCheck = true },
                        onProjectTap: { project in
                            selectedProject = project
                        },
                        onShare: { project in
                            shareInput = .project(id: project.id, name: project.name)
                        },
                        onRoomTap: { project, scan in
                            selectedScanDetail = ScanDetailDestination(
                                projectID: project.id,
                                projectName: project.name,
                                scan: scan
                            )
                        },
                        onToggleExpansion: { projectID in
                            viewModel.toggleExpansion(for: projectID)
                        },
                        onEdit: { project in
                            projectToEdit = project
                        },
                        onDelete: { project in
                            projectPendingDelete = project
                        }
                    )
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 24)
            }
            .refreshable {
                await viewModel.refreshProjects()
            }
            .accessibilityIdentifier("projects.list")
        }
    }
}

private struct ProjectsPresentationModifier: ViewModifier {
    @Binding var selectedProject: ProjectSummary?
    @Binding var selectedScanDetail: ScanDetailDestination?
    @Binding var shareInput: ShareScreenInput?
    @Binding var showsScanCheck: Bool
    @Binding var projectToEdit: ProjectSummary?
    @Binding var projectPendingDelete: ProjectSummary?
    @Binding var isShowingDetail: Bool
    var viewModel: ProjectsViewModel
    let projectsService: any ProjectsService
    let notesService: any NotesService
    let shareService: any ShareService
    var currentUserID: String

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $selectedProject) { project in
                projectDetailCover(for: project)
            }
            .fullScreenCover(item: $shareInput) { input in
                ShareView(input: input, service: shareService)
            }
            .navigationDestination(isPresented: $showsScanCheck) {
                ScanCheckView(
                    viewModel: ScanCheckViewModel(readinessService: RealScanReadinessService()),
                    // TODO: Route to scan capture flow (MOB-XX) when capture feature is implemented.
                    onStartScan: { showsScanCheck = false }
                )
            }
            .fullScreenCover(item: $selectedScanDetail) { destination in
                NavigationStack {
                    scanDetailView(for: destination)
                }
            }
            .onChange(of: selectedScanDetail) { _, destination in
                isShowingDetail = destination != nil
            }
            .task {
                await viewModel.loadInitialProjects()
            }
            .fullScreenCover(item: $projectToEdit) { project in
                editProjectCover(for: project)
            }
            .alert(
                String(localized: "projects.delete.title"),
                isPresented: Binding(
                    get: { projectPendingDelete != nil },
                    set: { if !$0 { projectPendingDelete = nil } }
                ),
                presenting: projectPendingDelete
            ) { project in
                Button(String(localized: "projects.delete.cancel"), role: .cancel) {
                    projectPendingDelete = nil
                }
                Button(String(localized: "projects.delete.confirm"), role: .destructive) {
                    Task {
                        await viewModel.deleteProject(id: project.id)
                        projectPendingDelete = nil
                    }
                }
            } message: { project in
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "projects.delete.message.format"),
                        project.roomScans.count,
                        project.name
                    )
                )
            }
            .onChange(of: viewModel.showsDeleteSuccessToast) { _, showsToast in
                guard showsToast else { return }
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    viewModel.dismissDeleteSuccessToast()
                }
            }
            .onChange(of: viewModel.showsActionErrorToast) { _, showsToast in
                guard showsToast, projectToEdit == nil else { return }
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    viewModel.dismissActionErrorToast()
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func scanDetailView(for destination: ScanDetailDestination) -> some View {
        ScanDetailView(
            viewModel: ScanDetailViewModel(
                projectID: destination.projectID,
                scan: destination.scan,
                currentUserID: currentUserID,
                service: projectsService
            ),
            projectID: destination.projectID,
            projectName: destination.projectName,
            notesService: notesService,
            shareService: shareService,
            onScanUpdated: { updatedScan in
                viewModel.applyUpdatedScan(
                    projectID: destination.projectID,
                    scan: updatedScan
                )
            },
            onScanDeleted: {
                viewModel.applyDeletedScan(
                    projectID: destination.projectID,
                    scanID: destination.scan.id
                )
            },
            // TODO: Implement scan sharing.
            onShare: {}
        )
    }

    private func projectDetailCover(for project: ProjectSummary) -> some View {
        ProjectDetailView(
            project: project,
            projectsService: projectsService,
            notesService: notesService,
            shareService: shareService,
            currentUserID: currentUserID,
            onScanUpdated: { updatedScan in
                viewModel.applyUpdatedScan(
                    projectID: project.id,
                    scan: updatedScan
                )
            },
            onScanDeleted: { scanID in
                viewModel.applyDeletedScan(
                    projectID: project.id,
                    scanID: scanID
                )
            }
        )
    }

    private func editProjectCover(for project: ProjectSummary) -> some View {
        NewProjectView(
            mode: .edit,
            initialName: project.name,
            initialDescription: project.description,
            onSave: { name, description in
                Task {
                    let didUpdate = await viewModel.updateProject(
                        id: project.id,
                        name: name,
                        description: description
                    )
                    if didUpdate {
                        projectToEdit = nil
                    }
                }
            },
            onCancel: {
                projectToEdit = nil
                viewModel.dismissActionErrorToast()
            }
        )
        .alert(
            String(localized: "projects.action.error"),
            isPresented: Binding(
                get: { viewModel.showsActionErrorToast },
                set: { if !$0 { viewModel.dismissActionErrorToast() } }
            )
        ) {
            Button(String(localized: "projects.action.error.dismiss"), role: .cancel) {
                viewModel.dismissActionErrorToast()
            }
        }
    }
}

private struct RefreshingBannerView: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text("projects.refreshing")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("projects.refreshing")
    }
}

private struct LoadingMoreFooterView: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text("projects.loadingMore")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.quaternary.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.top, 4)
        .accessibilityIdentifier("projects.loadingMore")
    }
}

private struct ProjectsContentSection: View {
    let viewModel: ProjectsViewModel
    let onNewScan: () -> Void
    let onProjectTap: (ProjectSummary) -> Void
    let onShare: (ProjectSummary) -> Void
    let onRoomTap: (ProjectSummary, RoomScanSummary) -> Void
    let onToggleExpansion: (ProjectSummary.ID) -> Void
    let onEdit: (ProjectSummary) -> Void
    let onDelete: (ProjectSummary) -> Void

    var body: some View {
        VStack(spacing: 16) {
            PrimaryActionButton(
                title: String(localized: "home.newScan"),
                systemImageName: "plus",
                color: AppColors.brandBlueBottom,
                action: onNewScan,
                accessibilityIdentifier: "home.newScan"
            )
            .padding(.bottom, 6)

            if viewModel.showsSearchEmptyState {
                SearchEmptyStateView(query: viewModel.trimmedSearchQuery)
            }

            ForEach(viewModel.visibleProjects) { visibleProject in
                ProjectCardView(
                    project: visibleProject.project,
                    visibleRoomScans: visibleProject.roomScans,
                    isExpanded: viewModel.isExpanded(visibleProject.project.id),
                    showsExpandControl: !viewModel.hasActiveSearch
                        && viewModel.showsExpandControl(for: visibleProject.project),
                    searchQuery: viewModel.trimmedSearchQuery,
                    onProjectTap: {
                        onProjectTap(visibleProject.project)
                    },
                    onShare: {
                        onShare(visibleProject.project)
                    },
                    onToggleExpansion: {
                        onToggleExpansion(visibleProject.project.id)
                    },
                    onRoomTap: { scan in
                        onRoomTap(visibleProject.project, scan)
                    },
                    onEdit: {
                        onEdit(visibleProject.project)
                    },
                    onDelete: {
                        onDelete(visibleProject.project)
                    }
                )
                .onAppear {
                    Task {
                        await viewModel.loadNextPageIfNeeded(currentProjectID: visibleProject.project.id)
                    }
                }
            }

            if viewModel.isLoadingNextPage && !viewModel.hasActiveSearch {
                LoadingMoreFooterView()
            }
        }
    }
}

private struct SearchBarView: View {
    @Binding var searchQuery: String
    let isSearchFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(String(localized: "projects.search.placeholder"), text: $searchQuery)
                .font(.body)
                .focused(isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("projects.search.input")

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    isSearchFocused.wrappedValue = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "projects.search.clear"))
                .accessibilityIdentifier("projects.search.clear")
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(.quaternary.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            isSearchFocused.wrappedValue = true
        }
        .accessibilityIdentifier("projects.search")
    }
}

private struct SearchEmptyStateView: View {
    let query: String

    var body: some View {
        ContentUnavailableView(
            String.localizedStringWithFormat(
                String(localized: "projects.search.empty.format"),
                query
            ),
            systemImage: "magnifyingglass"
        )
        .accessibilityIdentifier("projects.search.emptyState")
    }
}

private struct PaginationErrorToast: View {
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("projects.pagination.error")
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(2)

            Spacer()

            Button(String(localized: "projects.pagination.retry"), action: onRetry)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .accessibilityIdentifier("projects.pagination.retry")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.black.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("projects.pagination.toast")
    }
}

private struct DeleteSuccessToast: View {
    var body: some View {
        Text("projects.delete.success")
            .font(.subheadline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.black.opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("projects.delete.toast")
    }
}

private struct ActionErrorToast: View {
    var body: some View {
        Text("projects.action.error")
            .font(.subheadline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.black.opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("projects.action.error.toast")
    }
}

#Preview {
    let service = MockProjectsService(simulatedDelayNanoseconds: 0)
    return ProjectsView(
        viewModel: ProjectsViewModel(service: service),
        projectsService: service,
        notesService: MockNotesService(),
        shareService: MockShareService(simulatedDelayNanoseconds: 0),
        currentUserID: AuthenticationSession.mockAppleUser.user.id
    )
}

private struct ScanDetailDestination: Hashable, Identifiable {
    let projectID: String
    let projectName: String?
    let scan: RoomScanSummary

    var id: String {
        "\(projectID)-\(scan.id)"
    }
}
