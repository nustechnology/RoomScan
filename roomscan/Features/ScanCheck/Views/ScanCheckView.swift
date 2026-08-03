//
//  ScanCheckView.swift
//  roomscan
//

import SwiftUI

struct ScanCheckView: View {
    @State var viewModel: ScanCheckViewModel
    let onStartScan: () -> Void
    var onCancel: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: AppSpacing.extraLarge) {
                    bannerCard
                    readinessChecksSection
                    tipsSection
                }
                .padding(.horizontal, AppSpacing.extraLarge)
                .padding(.top, AppSpacing.large)
                .padding(.bottom, AppSpacing.tripleExtraLarge)
            }

            startScanButton
        }
        .navigationTitle(String(localized: "scancheck.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onCancel?()
                    dismiss()
                } label: {
                    Text(String(localized: "scanning.action.cancel"))
                        .font(.body)
                }
                .accessibilityIdentifier("scancheck.cancelButton")
            }
        }
        .background(AppColors.background)
        .task {
            await viewModel.runAllChecks()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                viewModel.handleForegroundReturn()
            }
        }
    }

    private func handleCameraPermissionAction() {
        if viewModel.cameraPermissionNeedsSettings {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        } else {
            Task { await viewModel.handleCameraPermissionTap() }
        }
    }

    // MARK: - Banner

    private var bannerCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(String(localized: "scancheck.banner.title"))
                .appTypography(AppTypography.headingMedium)
                .foregroundStyle(AppColors.primaryText)

            Text(String(localized: "scancheck.banner.subtitle"))
                .appTypography(AppTypography.bodySmall)
                .foregroundStyle(AppColors.secondaryText)
                .lineLimit(nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.large)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("scancheck.banner")
    }

    // MARK: - Readiness Checks

    private var readinessChecksSection: some View {
        VStack(spacing: AppSpacing.medium) {
            SectionHeaderView(title: String(localized: "scancheck.section.title"))

            ReadinessCheckRowView(
                label: String(localized: "scancheck.device.label"),
                status: viewModel.deviceSupportStatus,
                onAction: nil,
                accessibilityIdentifier: "scancheck.device"
            )

            ReadinessCheckRowView(
                label: String(localized: "scancheck.cameraPermission.label"),
                status: viewModel.cameraPermissionStatus,
                onAction: {
                    handleCameraPermissionAction()
                },
                accessibilityIdentifier: "scancheck.cameraPermission"
            )

            ReadinessCheckRowView(
                label: String(localized: "scancheck.storage.label"),
                status: viewModel.storageStatus,
                onAction: nil,
                accessibilityIdentifier: "scancheck.storage"
            )

            ReadinessCheckRowView(
                label: String(localized: "scancheck.cameraStatus.label"),
                status: viewModel.cameraAvailabilityStatus,
                onAction: nil,
                accessibilityIdentifier: "scancheck.cameraStatus"
            )
        }
    }

    // MARK: - Tips

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(String(localized: "scancheck.tips.title"))
                .appTypography(AppTypography.bodySmallStrong)
                .foregroundStyle(AppColors.primaryText)
                .accessibilityIdentifier("scancheck.tips.title")

            Text(String(localized: "scancheck.tips.content"))
                .appTypography(AppTypography.bodySmall)
                .foregroundStyle(AppColors.secondaryText)
                .lineLimit(nil)
                .accessibilityIdentifier("scancheck.tips.content")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Start Scan Button

    private var startScanButton: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.5)

            Button {
                onStartScan()
            } label: {
                Text(String(localized: "scancheck.startScan"))
                    .appTypography(AppTypography.labelButton)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .foregroundStyle(.white)
                    .background(viewModel.allChecksPassed ? Color.blue : Color.gray)
                    .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
            }
            .disabled(!viewModel.allChecksPassed)
            .accessibilityIdentifier("scancheck.startScan")
            .padding(.horizontal, AppSpacing.extraLarge)
            .padding(.vertical, AppSpacing.large)
        }
        .background(AppColors.background)
    }
}

// MARK: - Section Header

private struct SectionHeaderView: View {
    let title: String

    var body: some View {
        Text(title)
            .appTypography(AppTypography.bodySmallStrong)
            .foregroundStyle(AppColors.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("scancheck.section")
    }
}

// MARK: - Readiness Check Row

private struct ReadinessCheckRowView: View {
    let label: String
    let status: ReadinessStatus
    let onAction: (() -> Void)?
    let accessibilityIdentifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.extraSmall) {
            HStack(spacing: AppSpacing.medium) {
                statusIcon
                    .frame(width: 24, height: 24)

                Text(label)
                    .appTypography(AppTypography.bodyMedium)
                    .foregroundStyle(AppColors.primaryText)
                    .lineLimit(2)

                Spacer(minLength: AppSpacing.small)

                if let actionLabel = actionLabel {
                    Button(actionLabel) {
                        onAction?()
                    }
                    .appTypography(AppTypography.bodySmallStrong)
                    .foregroundStyle(.blue)
                    .accessibilityIdentifier("\(accessibilityIdentifier).action")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if onAction != nil {
                    onAction?()
                }
            }

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .appTypography(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.error)
                    .lineLimit(nil)
                    .padding(.leading, 24 + AppSpacing.medium)
                    .accessibilityIdentifier("\(accessibilityIdentifier).error")
            }
        }
        .padding(AppSpacing.medium)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.small))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var statusIcon: some View {
        Group {
            switch status {
            case .checking:
                ProgressView()
                    .controlSize(.small)

            case .passed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 20))

            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(AppColors.error)
                    .font(.system(size: 20))
            }
        }
    }

    private var actionLabel: String? {
        guard case .failed(_, let label) = status, let label else {
            return nil
        }
        return label
    }

    private var errorMessage: String? {
        guard case .failed(let message, _) = status else {
            return nil
        }
        return message
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ScanCheckView(
            viewModel: ScanCheckViewModel(readinessService: RealScanReadinessService()),
            onStartScan: {}
        )
    }
}
