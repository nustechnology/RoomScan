//
//  ProjectDetailView.swift
//  roomscan
//

import SwiftUI

struct ProjectDetailView: View {
    let project: ProjectSummary
    let projectsService: any ProjectsService
    let notesService: any NotesService
    let shareService: any ShareService
    let currentUserID: String
    var accessPolicy: DetailAccessPolicy = .editable
    var onScanUpdated: (RoomScanSummary) -> Void = { _ in }
    var onScanDeleted: (RoomScanSummary.ID) -> Void = { _ in }
    var onAddScan: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var selectedScanDetail: ProjectDetailScanDestination?
    @State private var shareInput: ShareScreenInput?
    @State private var displayedProject: ProjectSummary
    @State private var roomScans: [RoomScanSummary] = []
    @State private var isLoadingDetail = false
    @State private var showsDetailLoadError = false

    init(
        project: ProjectSummary,
        projectsService: any ProjectsService,
        notesService: any NotesService,
        shareService: any ShareService,
        currentUserID: String,
        accessPolicy: DetailAccessPolicy = .editable,
        onScanUpdated: @escaping (RoomScanSummary) -> Void = { _ in },
        onScanDeleted: @escaping (RoomScanSummary.ID) -> Void = { _ in },
        onAddScan: ((String) -> Void)? = nil
    ) {
        self.project = project
        self.projectsService = projectsService
        self.notesService = notesService
        self.shareService = shareService
        self.currentUserID = currentUserID
        self.accessPolicy = accessPolicy
        self.onScanUpdated = onScanUpdated
        self.onScanDeleted = onScanDeleted
        self.onAddScan = onAddScan
        _displayedProject = State(initialValue: project)
    }

    private var showsOwnerActions: Bool {
        ProjectDetailPresentation.showsOwnerActions(for: accessPolicy)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if isLoadingDetail {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .accessibilityIdentifier("projects.detail.loading")
                    }

                    projectMetadata

                    Text(scansTitle)
                        .font(.title3.bold())
                        .padding(.top, 24)
                        .padding(.bottom, 14)
                        .accessibilityIdentifier("projects.detail.scanCount.\(displayedProject.id)")

                    VStack(spacing: 0) {
                        switch detailScansContentState {
                        case .empty:
                            Text("projects.detail.emptyScans.message")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 28)
                                .accessibilityIdentifier("projects.detail.emptyScans")
                        case .remoteOnly:
                            Text("projects.detail.remoteScansUnavailable.message")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 28)
                                .accessibilityIdentifier("projects.detail.remoteScansUnavailable")
                        case .local:
                            ForEach(Array(roomScans.enumerated()), id: \.element.id) { index, scan in
                                RoomScanRowView(
                                    scan: scan,
                                    onTap: {
                                        selectedScanDetail = ProjectDetailScanDestination(
                                            projectID: displayedProject.id,
                                            scan: scan
                                        )
                                    }
                                )
                                    .padding(12)

                                if index < roomScans.count - 1 {
                                    Divider()
                                        .padding(.leading, 12)
                                }
                            }
                        }
                    }
                    .background(AppColors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(.secondary.opacity(0.35), lineWidth: 1)
                    }

                    if showsOwnerActions {
                        VStack(spacing: 12) {
                            PrimaryActionButton(
                                title: String(localized: "projects.detail.addScan"),
                                systemImageName: "plus",
                                color: AppColors.background,
                                action: {
                                    onAddScan?(displayedProject.id)
                                },
                                foregroundColor: .primary,
                                borderColor: .secondary.opacity(0.35),
                                cornerRadius: 16,
                                accessibilityIdentifier: "projects.detail.addScan"
                            )

                            PrimaryActionButton(
                                title: String(localized: "projects.detail.shareProject"),
                                systemImageName: "square.and.arrow.up",
                                color: AppColors.background,
                                action: openShareProject,
                                foregroundColor: .primary,
                                borderColor: .secondary.opacity(0.35),
                                cornerRadius: 16,
                                accessibilityIdentifier: "projects.detail.shareProject"
                            )
                        }
                        .padding(.top, 20)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
            }
            .background(AppColors.background)
            .task {
                roomScans = project.roomScans
                await loadProjectDetail()
            }
            .alert("projects.action.error", isPresented: $showsDetailLoadError) {
                Button("projects.action.error.dismiss", role: .cancel) {}
                Button("projects.pagination.retry") {
                    Task { await loadProjectDetail() }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.semibold))
                            .frame(width: 36, height: 36)
                    }
                    .foregroundStyle(.primary)
                    .accessibilityLabel(String(localized: "common.back"))
                    .accessibilityIdentifier("projects.detail.close")
                }

                ToolbarItem(placement: .principal) {
                    Text(displayedProject.name)
                        .font(.title2.bold())
                        .lineLimit(1)
                        .accessibilityIdentifier("projects.detail.title.\(displayedProject.id)")
                }
            }
            .accessibilityIdentifier("projects.detail")
            .fullScreenCover(item: $selectedScanDetail) { destination in
                NavigationStack {
                    ScanDetailView(
                        viewModel: ScanDetailViewModel(
                            projectID: destination.projectID,
                            scan: destination.scan,
                            currentUserID: currentUserID,
                            service: projectsService,
                            accessPolicy: accessPolicy
                        ),
                        projectID: destination.projectID,
                        projectName: displayedProject.name,
                        notesService: notesService,
                        shareService: shareService,
                        accessPolicy: accessPolicy,
                        onScanUpdated: handleScanUpdated,
                        onScanDeleted: {
                            handleScanDeleted(scanID: destination.scan.id)
                        },
                        onShare: {}
                    )
                }
            }
            .fullScreenCover(item: $shareInput) { input in
                ShareView(input: input, service: shareService)
            }
        }
        .background(AppColors.background)
    }

    private var projectMetadata: some View {
        VStack(spacing: 0) {
            DetailMetadataRow(
                title: "projects.detail.metadata.owner.label",
                value: displayedProject.ownerName,
                accessibilityIdentifier: "projects.detail.metadata.owner"
            )
            metadataDivider
            DetailMetadataRow(
                title: "projects.detail.metadata.created.label",
                value: createdDateText,
                accessibilityIdentifier: "projects.detail.metadata.created"
            )
            metadataDivider
            DetailMetadataRow(
                title: "projects.detail.metadata.shared.label",
                value: sharedUserCountText,
                showsDisclosure: showsOwnerActions,
                accessibilityIdentifier: "projects.detail.metadata.shared",
                action: shareMetadataAction
            )
            metadataDivider
        }
    }

    private var createdDateText: String {
        ProjectDetailPresentation.createdDateText(for: displayedProject.createdAt)
    }

    private var sharedUserCountText: String {
        ProjectDetailPresentation.sharedUserCountText(for: displayedProject.sharedUserCount)
    }

    private var scansTitle: String {
        ProjectDetailPresentation.scansTitle(
            for: max(displayedProject.scanCount, roomScans.count)
        )
    }

    private var detailScansContentState: ProjectScansContentState {
        .resolve(localScanCount: roomScans.count, remoteScanCount: displayedProject.scanCount)
    }

    private var shareMetadataAction: (() -> Void)? {
        showsOwnerActions ? { openShareProject() } : nil
    }

    private var metadataDivider: some View {
        Rectangle()
            .fill(.secondary.opacity(0.45))
            .frame(height: 1)
    }

    private func openShareProject() {
        shareInput = .project(id: displayedProject.id, name: displayedProject.name)
    }

    private func loadProjectDetail() async {
        isLoadingDetail = true
        defer { isLoadingDetail = false }

        do {
            let remote = try await projectsService.fetchProject(id: project.id)
            // fetchProject already merges API scans with the local store; also merge
            // any fresher in-memory scans from this screen (e.g. mid-session edits).
            let mergedScans = ProjectAPIMapping.mergeRoomScans(
                apiScans: remote.roomScans,
                localScans: roomScans
            )
            displayedProject = ProjectSummary(
                id: remote.id,
                name: remote.name,
                ownerName: remote.ownerName,
                createdAt: remote.createdAt,
                updatedAt: remote.updatedAt,
                description: remote.description,
                sharedUserCount: remote.sharedUserCount,
                roomScans: mergedScans,
                scanCount: max(remote.scanCount, mergedScans.count)
            )
            roomScans = mergedScans
            showsDetailLoadError = false
        } catch {
            showsDetailLoadError = true
        }
    }

    private func handleScanUpdated(_ updatedScan: RoomScanSummary) {
        guard let index = roomScans.firstIndex(where: { $0.id == updatedScan.id }) else { return }
        roomScans[index] = updatedScan
        onScanUpdated(updatedScan)
    }

    private func handleScanDeleted(scanID: RoomScanSummary.ID) {
        roomScans.removeAll { $0.id == scanID }
        onScanDeleted(scanID)
    }
}

private struct ProjectDetailScanDestination: Identifiable {
    let projectID: String
    let scan: RoomScanSummary

    var id: String {
        "\(projectID)-\(scan.id)"
    }
}

enum ProjectDetailPresentation {
    static func showsOwnerActions(for accessPolicy: DetailAccessPolicy) -> Bool {
        accessPolicy.allowsOwnerActions
    }

    static func createdDateText(for date: Date, locale: Locale = .current) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year().locale(locale))
    }

    static func sharedUserCountText(for count: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "projects.detail.sharedUsers.count.format"),
            count
        )
    }

    static func scansTitle(for count: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "projects.detail.scans.title.format"),
            count
        )
    }
}

private struct DetailMetadataRow: View {
    let title: LocalizedStringKey
    let value: String
    var showsDisclosure = false
    var accessibilityIdentifier: String?
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 14)
        .applyAccessibilityIdentifier(accessibilityIdentifier)
    }

    private var rowContent: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer(minLength: 16)

            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func applyAccessibilityIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}
