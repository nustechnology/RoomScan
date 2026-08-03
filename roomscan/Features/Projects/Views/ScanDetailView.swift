//
//  ScanDetailView.swift
//  roomscan
//

import SwiftUI

struct ScanDetailView: View {
    @State var viewModel: ScanDetailViewModel
    let onScanUpdated: (RoomScanSummary) -> Void
    let onScanDeleted: () -> Void
    var onOpen3DModel: (() -> Void)?
    let onShare: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showsRenameAlert = false
    @State private var showsDeleteConfirmation = false

    private var canOpen3DModel: Bool { onOpen3DModel != nil }

    private var open3DModelButtonTitle: String {
        if canOpen3DModel {
            String(localized: "scanDetail.open3DModel")
        } else {
            String(localized: "scanDetail.open3DModel.unavailable")
        }
    }

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
        .toolbar {
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
                        Button(String(localized: "scanDetail.menu.share"), action: onShare)
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
                Task {
                    let didRename = await viewModel.renameScan()
                    if didRename {
                        onScanUpdated(viewModel.scan)
                    }
                }
            }
        }
        .alert(
            String(localized: "scanDetail.delete.title"),
            isPresented: $showsDeleteConfirmation
        ) {
            Button(String(localized: "scanDetail.delete.cancel"), role: .cancel) {}
            Button(String(localized: "scanDetail.delete.confirm"), role: .destructive) {
                Task {
                    let didDelete = await viewModel.deleteScan()
                    if didDelete {
                        onScanDeleted()
                        dismiss()
                    }
                }
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
        .disabled(viewModel.isPerformingAction)
    }

    private var open3DModelButton: some View {
        PrimaryActionButton(
            title: open3DModelButtonTitle,
            systemImageName: "cube",
            color: AppColors.brandBlueBottom,
            action: { onOpen3DModel?() },
            accessibilityIdentifier: "scanDetail.open3DModel"
        )
        .disabled(!canOpen3DModel)
        .opacity(canOpen3DModel ? 1 : 0.5)
    }

    @ViewBuilder
    private var thumbnailCard: some View {
        if let onOpen3DModel {
            Button(action: onOpen3DModel) {
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
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
        .contentShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
    }

    private var metadataSection: some View {
        VStack(spacing: 0) {
            metadataRow(
                label: String(localized: "scanDetail.createdBy"),
                value: viewModel.createdByText,
                accessibilityIdentifier: "scanDetail.createdBy"
            )
            Divider()
            metadataRow(
                label: String(localized: "scanDetail.date"),
                value: viewModel.formattedDate,
                accessibilityIdentifier: "scanDetail.date"
            )
            Divider()
            metadataRow(
                label: String(localized: "scanDetail.notes"),
                value: viewModel.notesCountText,
                accessibilityIdentifier: "scanDetail.notes"
            )
            Divider()
            statusRow
        }
    }

    private func metadataRow(
        label: String,
        value: String,
        accessibilityIdentifier: String
    ) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(AppColors.secondaryText)
                .appTypography(AppTypography.bodySmall)

            Spacer(minLength: AppSpacing.small)

            Text(value)
                .appTypography(AppTypography.bodySmallStrong)
                .foregroundStyle(AppColors.primaryText)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
        .padding(.vertical, AppSpacing.medium)
    }

    private var statusRow: some View {
        HStack {
            Text("scanDetail.status")
                .appTypography(AppTypography.labelBadge)
                .foregroundStyle(AppColors.secondaryText)

            Spacer(minLength: AppSpacing.small)

            ScanSyncStatusBadge(
                syncStatus: viewModel.scan.syncStatus,
                showsRetry: viewModel.showsRetryUpload,
                onRetry: {
                    Task {
                        let didRetry = await viewModel.retryUpload()
                        if didRetry {
                            onScanUpdated(viewModel.scan)
                        }
                    }
                }
            )
        }
        .padding(.vertical, AppSpacing.medium)
        .accessibilityIdentifier("scanDetail.status")
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
            onScanUpdated: { _ in },
            onScanDeleted: {},
            onShare: {}
        )
    }
}
