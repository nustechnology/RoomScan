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

    @State private var projectToEdit: ProjectSummary?
    @State private var projectPendingDelete: ProjectSummary?
    @FocusState private var isSearchFocused: Bool

    @State private var scanningSourceProjectID: String?
    @State private var pendingScanSourceProjectID: String?
    @State private var recoveredDraft: RoomScanDraft?
    @State private var recoveredDraftToPrompt: RoomScanDraft?
    @State private var savedScanForDetails: RoomScanSummary?
    @State private var pendingSavedScanForDetails: RoomScanSummary?
    @State private var showsScanFlow = false

    private let storageService: ScanStorageService = LocalScanStorageService()

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
                projectToEdit: $projectToEdit,
                projectPendingDelete: $projectPendingDelete,
                isShowingDetail: $isShowingDetail,
                viewModel: viewModel,
                projectsService: projectsService,
                notesService: notesService,
                shareService: shareService,
                currentUserID: currentUserID,
                showsScanFlow: $showsScanFlow,
                scanningSourceProjectID: $scanningSourceProjectID,
                pendingScanSourceProjectID: $pendingScanSourceProjectID,
                recoveredDraft: $recoveredDraft,
                recoveredDraftToPrompt: $recoveredDraftToPrompt,
                savedScanForDetails: $savedScanForDetails,
                pendingSavedScanForDetails: $pendingSavedScanForDetails,
                storageService: storageService
            ))
    }

    private var toastOverlay: some View {
        ZStack(alignment: .bottom) {
            content
                .transaction { transaction in
                    // Keep list updates under the delete overlay from animating,
                    // so hiding the overlay does not flash card layout changes.
                    if viewModel.isDeletingProject {
                        transaction.disablesAnimations = true
                    }
                }

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
                        onNewScan: {
                            scanningSourceProjectID = nil
                            showsScanFlow = true
                        },
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
                        },
                        onAddScan: { project in
                            scanningSourceProjectID = project.id
                            showsScanFlow = true
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
    let onAddScan: (ProjectSummary) -> Void

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
                    onEdit: {
                        onEdit(visibleProject.project)
                    },
                    onDelete: {
                        onDelete(visibleProject.project)
                    },
                    onRoomTap: { scan in
                        onRoomTap(visibleProject.project, scan)
                    },
                    onAddScan: {
                        onAddScan(visibleProject.project)
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
