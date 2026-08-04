//
//  SharedWithMeView.swift
//  roomscan
//

import SwiftUI

struct SharedWithMeView: View {
    @State var viewModel: SharedWithMeViewModel
    let projectsService: any ProjectsService
    let notesService: any NotesService
    let shareService: any ShareService
    let currentUserID: String

    @State private var selectedProject: ProjectSummary?
    @State private var selectedScan: SharedScanDetailDestination?
    @State private var toastTask: Task<Void, Never>?

    init(
        viewModel: SharedWithMeViewModel,
        projectsService: any ProjectsService,
        notesService: any NotesService,
        shareService: any ShareService,
        currentUserID: String
    ) {
        _viewModel = State(initialValue: viewModel)
        self.projectsService = projectsService
        self.notesService = notesService
        self.shareService = shareService
        self.currentUserID = currentUserID
    }

    var body: some View {
        VStack(spacing: 0) {
            subTabPicker
                .padding(.horizontal, AppSpacing.extraLarge)
                .padding(.top, AppSpacing.medium)
                .padding(.bottom, AppSpacing.small)

            content
        }
        .background(AppColors.background)
        .fullScreenCover(item: $selectedProject) { project in
            ProjectDetailView(
                project: project,
                projectsService: projectsService,
                notesService: notesService,
                shareService: shareService,
                currentUserID: currentUserID,
                accessPolicy: .readOnly
            )
        }
        .fullScreenCover(item: $selectedScan) { destination in
            sharedScanDetailCover(for: destination)
        }
        .task {
            await viewModel.loadInitialContent()
        }
        .alert(alertTitle, isPresented: alertBinding) {
            Button(String(localized: "shared.alert.cancel"), role: .cancel) {
                viewModel.dismissAlert()
            }
            Button(String(localized: "shared.remove.action"), role: .destructive) {
                Task { await viewModel.confirmPendingAlertAction() }
            }
        } message: {
            Text(alertMessage)
        }
        .overlay(alignment: .bottom) {
            if let toastMessage = viewModel.toastMessage {
                SharedToastView(message: toastMessage)
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityIdentifier("shared.toast")
            }
        }
        .animation(.default, value: viewModel.toastMessage)
        .onChange(of: viewModel.toastMessage) { _, message in
            toastTask?.cancel()
            guard message != nil else { return }
            toastTask = Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard !Task.isCancelled else { return }
                viewModel.dismissToast()
            }
        }
    }

    private var subTabPicker: some View {
        HStack(spacing: 0) {
            ForEach(SharedWithMeViewModel.SubTab.allCases, id: \.self) { tab in
                Button {
                    viewModel.selectSubTab(tab)
                } label: {
                    VStack(spacing: 10) {
                        Text(tab.localizedTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(
                                viewModel.selectedSubTab == tab
                                    ? AppColors.brandBlueBottom
                                    : AppColors.secondaryText
                            )

                        Rectangle()
                            .fill(
                                viewModel.selectedSubTab == tab
                                    ? AppColors.brandBlueBottom
                                    : Color.clear
                            )
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(viewModel.selectedSubTab == tab ? .isSelected : [])
                .accessibilityIdentifier(tab.accessibilityIdentifier)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.quaternary)
                .frame(height: 1)
        }
        .accessibilityIdentifier("shared.subtabs")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.selectedSubTab {
        case .projects:
            SharedProjectsContentView(
                viewState: viewModel.projectsViewState,
                projects: viewModel.projects,
                onRetry: { await viewModel.retrySelectedTab() },
                onRefresh: { await viewModel.refreshSelectedTab() },
                onTap: handleProjectTap,
                onRemove: { viewModel.requestRemove(scope: .project, id: $0) }
            )
        case .scans:
            SharedScansContentView(
                viewState: viewModel.scansViewState,
                scans: viewModel.scans,
                onRetry: { await viewModel.retrySelectedTab() },
                onRefresh: { await viewModel.refreshSelectedTab() },
                onTap: handleScanTap,
                onRemove: { viewModel.requestRemove(scope: .scan, id: $0) }
            )
        }
    }

    private func sharedScanDetailCover(for destination: SharedScanDetailDestination) -> some View {
        NavigationStack {
            ScanDetailView(
                viewModel: ScanDetailViewModel(
                    projectID: destination.projectID,
                    scan: destination.scan,
                    currentUserID: currentUserID,
                    service: projectsService,
                    accessPolicy: .readOnly
                ),
                projectID: destination.projectID,
                projectName: nil,
                notesService: notesService,
                shareService: shareService,
                accessPolicy: .readOnly,
                onScanUpdated: { _ in },
                onScanDeleted: { selectedScan = nil },
                onShare: {}
            )
        }
    }

    private func handleProjectTap(_ project: SharedProjectItem) {
        guard let result = viewModel.handleItemTap(scope: .project, id: project.id) else { return }
        if case .openProject(let detail) = result {
            selectedProject = detail
        }
    }

    private func handleScanTap(_ scan: SharedScanItem) {
        guard let result = viewModel.handleItemTap(scope: .scan, id: scan.id) else { return }
        if case .openScan(let projectID, let detailScan) = result {
            selectedScan = SharedScanDetailDestination(projectID: projectID, scan: detailScan)
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingAlert != nil },
            set: { if !$0 { viewModel.dismissAlert() } }
        )
    }

    private var alertTitle: String {
        guard let pendingAlert = viewModel.pendingAlert else { return "" }
        switch pendingAlert {
        case .inactiveTap(_, _, let status):
            switch status {
            case .accessRevoked:
                return String(localized: "shared.alert.accessRevoked.title")
            case .itemDeleted:
                return String(localized: "shared.alert.unavailable.title")
            case .active:
                return String(localized: "shared.alert.remove.title")
            }
        case .confirmRemove:
            return String(localized: "shared.alert.remove.title")
        }
    }

    private var alertMessage: String {
        guard let pendingAlert = viewModel.pendingAlert else { return "" }
        switch pendingAlert {
        case .inactiveTap(let scope, _, _):
            switch scope {
            case .project:
                return String(localized: "shared.alert.inactive.project.message")
            case .scan:
                return String(localized: "shared.alert.inactive.scan.message")
            }
        case .confirmRemove:
            return String(localized: "shared.alert.remove.message")
        }
    }
}

private struct SharedProjectsContentView: View {
    let viewState: SharedWithMeViewModel.ViewState
    let projects: [SharedProjectItem]
    let onRetry: () async -> Void
    let onRefresh: () async -> Void
    let onTap: (SharedProjectItem) -> Void
    let onRemove: (String) -> Void

    var body: some View {
        switch viewState {
        case .idle, .loading:
            ProgressView(String(localized: "shared.loading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("shared.projects.loading")

        case .empty:
            ContentUnavailableView(
                String(localized: "shared.empty.projects"),
                systemImage: "person.2"
            )
            .accessibilityIdentifier("shared.projects.empty")

        case .failed:
            ContentUnavailableView {
                Label(String(localized: "shared.load.error"), systemImage: "wifi.exclamationmark")
            } actions: {
                Button(String(localized: "shared.load.retry")) {
                    Task { await onRetry() }
                }
                .accessibilityIdentifier("shared.projects.retry")
            }
            .accessibilityIdentifier("shared.projects.error")

        case .loaded:
            List {
                ForEach(projects) { project in
                    SharedProjectCardView(
                        project: project,
                        onTap: { onTap(project) },
                        onRemove: { onRemove(project.id) }
                    )
                    .sharedListRowStyle()
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            onRemove(project.id)
                        } label: {
                            Text("shared.remove.action")
                        }
                        .accessibilityIdentifier("shared.project.remove.\(project.id)")
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await onRefresh() }
            .accessibilityIdentifier("shared.projects.list")
        }
    }
}

private struct SharedScansContentView: View {
    let viewState: SharedWithMeViewModel.ViewState
    let scans: [SharedScanItem]
    let onRetry: () async -> Void
    let onRefresh: () async -> Void
    let onTap: (SharedScanItem) -> Void
    let onRemove: (String) -> Void

    var body: some View {
        switch viewState {
        case .idle, .loading:
            ProgressView(String(localized: "shared.loading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("shared.scans.loading")

        case .empty:
            ContentUnavailableView(
                String(localized: "shared.empty.scans"),
                systemImage: "cube"
            )
            .accessibilityIdentifier("shared.scans.empty")

        case .failed:
            ContentUnavailableView {
                Label(String(localized: "shared.load.error"), systemImage: "wifi.exclamationmark")
            } actions: {
                Button(String(localized: "shared.load.retry")) {
                    Task { await onRetry() }
                }
                .accessibilityIdentifier("shared.scans.retry")
            }
            .accessibilityIdentifier("shared.scans.error")

        case .loaded:
            List {
                ForEach(scans) { scan in
                    SharedScanCardView(
                        scan: scan,
                        onTap: { onTap(scan) },
                        onRemove: { onRemove(scan.id) }
                    )
                    .sharedListRowStyle()
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            onRemove(scan.id)
                        } label: {
                            Text("shared.remove.action")
                        }
                        .accessibilityIdentifier("shared.scan.remove.\(scan.id)")
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await onRefresh() }
            .accessibilityIdentifier("shared.scans.list")
        }
    }
}

private extension View {
    func sharedListRowStyle() -> some View {
        listRowInsets(EdgeInsets(
            top: AppSpacing.small,
            leading: AppSpacing.extraLarge,
            bottom: AppSpacing.small,
            trailing: AppSpacing.extraLarge
        ))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

private struct SharedScanDetailDestination: Identifiable, Hashable {
    var id: String { scan.id }
    let projectID: String
    let scan: RoomScanSummary
}

private struct SharedToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.black.opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    let sharedService = MockSharedService(simulatedDelayNanoseconds: 0)
    let projectsService = MockProjectsService(simulatedDelayNanoseconds: 0)
    return SharedWithMeView(
        viewModel: SharedWithMeViewModel(service: sharedService),
        projectsService: projectsService,
        notesService: MockNotesService(),
        shareService: MockShareService(simulatedDelayNanoseconds: 0),
        currentUserID: AuthenticationSession.mockAppleUser.user.id
    )
}
