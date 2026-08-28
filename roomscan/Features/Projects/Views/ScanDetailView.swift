//
//  ScanDetailView.swift
//  roomscan
//

import SwiftUI

struct ScanDetailView: View {
    private enum ConfirmationAction: Equatable {
        case rename
        case delete
    }

    @State var viewModel: ScanDetailViewModel
    let projectID: String?
    let projectName: String?
    let notesService: any NotesService
    let shareService: any ShareService
    var syncService: (any SyncService)?
    var accessPolicy: DetailAccessPolicy = .editable
    let onScanUpdated: (RoomScanSummary) -> Void
    let onScanDeleted: () -> Void
    let onShare: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showsRenameAlert = false
    @State private var showsDeleteConfirmation = false
    @State private var loadingAction: ConfirmationAction?
    @State private var viewerInput: ViewerInput?
    @State private var shareInput: ShareScreenInput?
    @State private var showsMissingScanAlert = false
    @State private var showsRetryCamera = false
    @State private var loadedThumbnail: UIImage?

    private var open3DModelButtonTitle: String { String(localized: "scanDetail.open3DModel") }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.extraLarge) {
                    thumbnailCard
                    metadataSection
                }
                .padding(.horizontal, AppSpacing.extraLarge)
                .padding(.top, AppSpacing.large)
                .padding(.bottom, AppSpacing.extraLarge)
            }

            open3DModelButton
                .padding(.horizontal, AppSpacing.extraLarge)
                .padding(.top, AppSpacing.medium)
                .padding(.bottom, AppSpacing.large)
        }
        .background(AppColors.background)
        .navigationTitle(viewModel.title)
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
                        .contentShape(Rectangle())
                }
                .foregroundStyle(AppColors.primaryText)
                .accessibilityLabel(String(localized: "common.back"))
                .accessibilityIdentifier("scanDetail.back")
            }
            ToolbarItem(placement: .principal) {
                Text(viewModel.title)
                    .appTypography(AppTypography.headingSmall)
                    .foregroundStyle(AppColors.primaryText)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.allowsOwnerActions {
                    Menu {
                        Button(String(localized: "scanDetail.menu.rename")) {
                            viewModel.beginRename()
                            showsRenameAlert = true
                        }
                        Button(String(localized: "scanDetail.menu.share"), action: openShare)
                        Button(String(localized: "scanDetail.menu.delete"), role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(String(localized: "scanDetail.menu.accessibility"))
                    .accessibilityIdentifier("scanDetail.menu")
                }
            }
        }
        .alert(
            String(localized: "scanDetail.rename.title"),
            isPresented: $showsRenameAlert
        ) {
            TextField(String(localized: "scanDetail.rename.placeholder"), text: $viewModel.renameDraft)
            Button(String(localized: "scanDetail.rename.cancel"), role: .cancel) {}
            Button(String(localized: "scanDetail.rename.save")) {
                performConfirmedAction(.rename)
            }
        }
        .alert(
            String(localized: "scanDetail.delete.title"),
            isPresented: $showsDeleteConfirmation
        ) {
            Button(String(localized: "scanDetail.delete.cancel"), role: .cancel) {}
            Button(String(localized: "scanDetail.delete.confirm"), role: .destructive) {
                performConfirmedAction(.delete)
            }
        } message: {
            Text("scanDetail.delete.message")
        }
        .alert(
            String(localized: "scanDetail.action.error"),
            isPresented: Binding(
                get: { viewModel.showsActionError },
                set: { if !$0 { viewModel.dismissActionError() } }
            )
        ) {
            Button(String(localized: "scanDetail.action.error.dismiss"), role: .cancel) {
                viewModel.dismissActionError()
            }
        }
        .fullScreenCover(item: $viewerInput) { input in
            ViewerView(
                input: input,
                notesService: notesService,
                modelDownloadService: viewModel.modelDownloadService,
                accessPolicy: accessPolicy,
                shareService: shareService,
                onBack: { viewerInput = nil }
            )
        }
        .fullScreenCover(item: $shareInput) { input in
            ShareView(input: input, service: shareService, syncService: syncService)
        }
        .overlay {
            if let loadingAction {
                loadingOverlay(for: loadingAction)
            } else if viewModel.isLoadingDetail {
                scanDetailLoadingOverlay
            }
        }
        .task {
            await viewModel.loadDetail()
            onScanUpdated(viewModel.scan)
        }
        .modifier(RetryScanPresentationModifier(
            showsMissingScanAlert: $showsMissingScanAlert,
            showsRetryCamera: $showsRetryCamera,
            projectID: projectID,
            viewModel: viewModel,
            onScanUpdated: onScanUpdated
        ))
        .disabled(viewModel.isPerformingAction || viewModel.isLoadingDetail)
    }

    private var open3DModelButton: some View {
        PrimaryActionButton(
            title: open3DModelButtonTitle,
            systemImageName: "cube",
            color: AppColors.brandBlueBottom,
            action: open3DModel,
            accessibilityIdentifier: "scanDetail.open3DModel"
        )
        .disabled(!viewModel.canOpen3DModel)
        .opacity(viewModel.canOpen3DModel ? 1 : 0.5)
    }

    @ViewBuilder
    private var thumbnailCard: some View {
        if viewModel.canOpen3DModel {
            Button(action: open3DModel) {
                thumbnailContent
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "scanDetail.thumbnail.accessibility"))
            .accessibilityIdentifier("scanDetail.thumbnail")
        } else {
            thumbnailContent
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "scanDetail.thumbnail.preview.accessibility"))
                .accessibilityIdentifier("scanDetail.thumbnail")
        }
    }

    private var thumbnailContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.78, green: 0.90, blue: 1.0),
                            Color(red: 0.88, green: 0.94, blue: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image("ScanThumbnail")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 160, maxHeight: 120)
                .accessibilityHidden(true)

            if let loadedThumbnail {
                Image(uiImage: loadedThumbnail)
                    .resizable()
                    .scaledToFill()
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
        .contentShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
        .task(id: viewModel.thumbnailPath) {
            loadedThumbnail = nil
            let thumbnail = await ScanThumbnailLoader.load(
                from: viewModel.thumbnailPath,
                maxPixelSize: thumbnailMaxPixelSize
            )
            guard !Task.isCancelled else { return }
            loadedThumbnail = thumbnail
        }
    }

    private var metadataSection: some View {
        VStack(spacing: 0) {
            metadataRow(
                label: "scanDetail.createdBy",
                value: viewModel.createdByText,
                accessibilityIdentifier: "scanDetail.createdBy",
                isLoading: viewModel.isLoadingDetail
            )
            Divider()
            metadataRow(
                label: "scanDetail.date",
                value: viewModel.formattedDate,
                accessibilityIdentifier: "scanDetail.date",
                isLoading: viewModel.isLoadingDetail
            )
            Divider()
            metadataRow(
                label: "scanDetail.notes",
                value: viewModel.notesCountText,
                accessibilityIdentifier: "scanDetail.notes",
                isLoading: viewModel.isLoadingDetail
            )
            Divider()
            statusRow
        }
    }

    private func metadataRow(
        label: LocalizedStringKey,
        value: String,
        accessibilityIdentifier: String,
        isLoading: Bool
    ) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(AppColors.secondaryText)
                .appTypography(AppTypography.bodySmall)

            Spacer(minLength: AppSpacing.small)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityIdentifier("\(accessibilityIdentifier).loading")
            } else {
                Text(value)
                    .appTypography(AppTypography.bodySmallStrong)
                    .foregroundStyle(AppColors.primaryText)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier(accessibilityIdentifier)
            }
        }
        .padding(.vertical, AppSpacing.medium)
    }

    private var statusRow: some View {
        HStack {
            Text("scanDetail.status")
                .appTypography(AppTypography.labelBadge)
                .foregroundStyle(AppColors.secondaryText)

            Spacer(minLength: AppSpacing.small)

            if viewModel.isLoadingDetail {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityIdentifier("scanDetail.status.loading")
            } else {
                ScanSyncStatusBadge(
                    syncStatus: viewModel.displaySyncStatus,
                    showsRetry: viewModel.showsRetryUpload,
                    onRetry: {
                        Task {
                            let didRetry = await viewModel.retryUpload()
                            if didRetry {
                                onScanUpdated(viewModel.scan)
                            } else if viewModel.needsRescanForRetry {
                                showsMissingScanAlert = true
                            }
                        }
                    }
                )
            }
        }
        .padding(.vertical, AppSpacing.medium)
        .accessibilityIdentifier("scanDetail.status")
    }
}

private extension ScanDetailView {
    var thumbnailMaxPixelSize: Int {
        let cardWidth = UIScreen.main.bounds.width - (AppSpacing.extraLarge * 2)
        return Int(max(cardWidth, 220) * UIScreen.main.scale)
    }

    func open3DModel() {
        viewerInput = ViewerInput(
            projectID: projectID,
            projectName: projectName,
            scanID: viewModel.scan.id,
            scanName: viewModel.scan.name,
            modelVersion: viewModel.viewerModelVersion,
            modelURL: viewModel.scan.localModelURL
        )
    }

    func openShare() {
        shareInput = .scan(
            projectID: projectID,
            projectName: projectName,
            scanID: viewModel.scan.id,
            scanName: viewModel.scan.name
        )
    }

    var scanDetailLoadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.12)
                .ignoresSafeArea()

            ProgressView()
                .controlSize(.large)
                .padding(AppSpacing.extraLarge)
                .background(AppColors.background, in: RoundedRectangle(cornerRadius: AppCornerRadius.large))
                .accessibilityIdentifier("scanDetail.loading")
        }
    }

    private func loadingOverlay(for action: ConfirmationAction) -> some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.medium) {
                ProgressView()
                    .controlSize(.large)
                Text(action == .rename ? "Updating scan…" : "Deleting scan…")
                    .appTypography(AppTypography.bodyMediumStrong)
                    .foregroundStyle(AppColors.primaryText)
            }
            .padding(AppSpacing.large)
            .frame(width: 180, height: 140)
            .background(AppColors.background, in: RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 12)
            .accessibilityIdentifier("scanDetail.action.loading")
        }
    }

    private func performConfirmedAction(_ action: ConfirmationAction) {
        loadingAction = action
        Task {
            defer { loadingAction = nil }
            switch action {
            case .rename:
                if await viewModel.renameScan() {
                    onScanUpdated(viewModel.scan)
                }
            case .delete:
                if await viewModel.deleteScan() {
                    onScanDeleted()
                    dismiss()
                }
            }
        }
    }
}

private struct RetryScanPresentationModifier: ViewModifier {
    @Binding var showsMissingScanAlert: Bool
    @Binding var showsRetryCamera: Bool
    let projectID: String?
    let viewModel: ScanDetailViewModel
    let onScanUpdated: (RoomScanSummary) -> Void

    func body(content: Content) -> some View {
        content.alert(String(localized: "scanDetail.missingScan.title"), isPresented: $showsMissingScanAlert) {
            Button(String(localized: "scanDetail.missingScan.scanAgain")) { showsRetryCamera = true }
            Button(String(localized: "scanDetail.missingScan.cancel"), role: .cancel) {}
        } message: {
            Text(LocalizedStringKey("scanDetail.missingScan.message"))
        }
        .fullScreenCover(isPresented: $showsRetryCamera) {
            CameraScanView(
                sourceProjectID: projectID,
                onFinish: { draft in
                    Task {
                        let didRetry = await viewModel.retryUpload(with: draft)
                        showsRetryCamera = false
                        guard didRetry else { return }
                        onScanUpdated(viewModel.scan)
                        LocalScanStorageService().clearDraftManifest()
                        draft.deleteManagedFiles()
                    }
                },
                onCancel: { showsRetryCamera = false }
            )
        }
    }
}

#Preview {
    NavigationStack {
        ScanDetailView(
            viewModel: ScanDetailViewModel(
                projectID: "project-1",
                scan: RoomScanSummary(
                    id: "scan-1",
                    name: "Living Room",
                    createdAt: Date(timeIntervalSince1970: 1_781_251_200),
                    localModelURL: nil,
                    thumbnailName: "thumbnail-0",
                    syncStatus: .synced,
                    creatorUserID: AuthenticationSession.mockAppleUser.user.id,
                    creatorDisplayName: "Mock Apple User",
                    notes: [
                        RoomScanNoteSummary(
                            id: "note-1",
                            text: "Note",
                            createdAt: Date()
                        ),
                        RoomScanNoteSummary(
                            id: "note-2",
                            text: "Note",
                            createdAt: Date()
                        ),
                        RoomScanNoteSummary(
                            id: "note-3",
                            text: "Note",
                            createdAt: Date()
                        )
                    ]
                ),
                currentUserID: AuthenticationSession.mockAppleUser.user.id,
                service: MockProjectsService(simulatedDelayNanoseconds: 0)
            ),
            projectID: "project-1",
            projectName: "Lakeside Remodel",
            notesService: MockNotesService(),
            shareService: MockShareService(simulatedDelayNanoseconds: 0),
            accessPolicy: .editable,
            onScanUpdated: { _ in },
            onScanDeleted: {},
            onShare: {}
        )
    }
}
