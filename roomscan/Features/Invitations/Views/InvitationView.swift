//
//  InvitationView.swift
//  roomscan
//

import SwiftUI

struct InvitationView: View {
    @State var viewModel: InvitationViewModel
    let onFinished: (InvitationViewModel.NavigationOutcome) -> Void

    var body: some View {
        NavigationStack {
            content
                .background(AppColors.background)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        backButton
                    }
                    ToolbarItem(placement: .principal) {
                        Text(viewModel.screenTitle)
                            .appTypography(AppTypography.headingSmall)
                            .foregroundStyle(AppColors.primaryText)
                            .accessibilityIdentifier("invitation.nav.title")
                    }
                }
                .toolbarBackground(AppColors.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
        .task {
            await viewModel.loadInvitation()
        }
        .alert(
            String(localized: "invitation.decline.title"),
            isPresented: Binding(
                get: { viewModel.showsDeclineConfirmation },
                set: { if !$0 { viewModel.cancelDecline() } }
            )
        ) {
            Button(String(localized: "invitation.decline.cancel"), role: .cancel) {
                viewModel.cancelDecline()
            }
            Button(String(localized: "invitation.decline.confirm"), role: .destructive) {
                Task { await viewModel.confirmDecline() }
            }
        } message: {
            Text(declineMessageKey)
        }
        .alert(
            blockingAlertTitle,
            isPresented: Binding(
                get: { viewModel.blockingAlert != nil && viewModel.blockingAlert != .expired },
                set: { if !$0 { viewModel.dismissBlockingAlert() } }
            )
        ) {
            Button(String(localized: "invitation.alert.ok"), role: .cancel) {
                viewModel.dismissBlockingAlert()
            }
        } message: {
            Text(blockingAlertMessage)
        }
        .alert(
            String(localized: "invitation.actionFailed.title"),
            isPresented: Binding(
                get: { viewModel.actionFailure != nil },
                set: { if !$0 { viewModel.dismissActionFailure() } }
            )
        ) {
            Button(String(localized: "invitation.decline.cancel"), role: .cancel) {
                viewModel.dismissActionFailure()
            }
            Button(String(localized: "invitation.loadFailed.retry")) {
                guard let failedAction = viewModel.actionFailure?.action else { return }
                Task { await viewModel.retryFailedAction(failedAction) }
            }
        } message: {
            Text(actionFailureMessage)
        }
        .onChange(of: viewModel.navigationOutcome) { _, outcome in
            guard let outcome else { return }
            onFinished(outcome)
            viewModel.clearNavigationOutcome()
        }
        .disabled(viewModel.isPerformingAction)
        .accessibilityIdentifier("invitation.screen")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("invitation.loading")

        case .failed(let error):
            if error == .expired {
                expiredContent
            } else if viewModel.blockingAlert != nil {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label(
                        String(localized: "invitation.loadFailed.title"),
                        systemImage: "exclamationmark.triangle"
                    )
                } description: {
                    Text(loadFailedMessage(for: error))
                } actions: {
                    Button(String(localized: "invitation.loadFailed.retry")) {
                        Task { await viewModel.loadInvitation() }
                    }
                    .accessibilityIdentifier("invitation.loadFailed.retry")
                }
            }

        case .loaded(let invitation):
            loadedContent(invitation)
        }
    }

    private var expiredContent: some View {
        ExpiredInvitationContent(
            scope: viewModel.pendingInvitation.scope,
            onBackToProjects: { viewModel.dismissBlockingAlert() }
        )
    }

    private func loadedContent(_ invitation: InvitationDetails) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    if invitation.showsThumbnail {
                                            InvitationThumbnailView()
                                                .accessibilityIdentifier("invitation.thumbnail")
                                        }

                    Text(invitation.title)
                        .appTypography(AppTypography.headingLarge)
                        .foregroundStyle(AppColors.primaryText)
                        .accessibilityIdentifier("invitation.itemTitle")

                    if let subtitleText = viewModel.subtitleText {
                        Text(subtitleText)
                            .appTypography(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.secondaryText)
                            .accessibilityIdentifier("invitation.subtitle")
                    }

                    metadataSection(invitation)
                }
                .padding(.horizontal, AppSpacing.extraLarge)
                .padding(.top, AppSpacing.large)
                .padding(.bottom, AppSpacing.extraLarge)
            }

            actionButtons
                .padding(.horizontal, AppSpacing.extraLarge)
                .padding(.top, AppSpacing.medium)
                .padding(.bottom, AppSpacing.large)
        }
    }

    private func metadataSection(_ invitation: InvitationDetails) -> some View {
        VStack(spacing: 0) {
            InvitationMetadataRow(
                title: String(localized: "invitation.metadata.owner"),
                value: invitation.ownerName,
                accessibilityIdentifier: "invitation.metadata.owner"
            )
            metadataDivider
            InvitationMetadataRow(
                title: viewModel.itemCountLabel,
                value: viewModel.itemCountValue,
                accessibilityIdentifier: "invitation.metadata.itemCount"
            )
            metadataDivider
            InvitationAccessRow()
        }
    }

    private var actionButtons: some View {
        HStack(spacing: AppSpacing.medium) {
            if !viewModel.hasExistingAccess {
                PrimaryActionButton(
                    title: String(localized: "invitation.action.decline"),
                    systemImageName: nil,
                    color: AppColors.background,
                    action: { viewModel.requestDecline() },
                    foregroundColor: AppColors.primaryText,
                    borderColor: AppColors.borderDefault,
                    cornerRadius: 18,
                    accessibilityIdentifier: "invitation.action.decline"
                )
            }

            PrimaryActionButton(
                title: primaryActionTitle,
                systemImageName: nil,
                color: AppColors.brandPrimary,
                action: performPrimaryAction,
                cornerRadius: 18,
                accessibilityIdentifier: primaryActionAccessibilityIdentifier
            )
        }
    }

    private var primaryActionTitle: String {
        if viewModel.hasExistingAccess {
            return String(localized: "invitation.action.open")
        }
        return String(localized: "invitation.action.accept")
    }

    private var primaryActionAccessibilityIdentifier: String {
        viewModel.hasExistingAccess ? "invitation.action.open" : "invitation.action.accept"
    }

    private func performPrimaryAction() {
        if viewModel.hasExistingAccess {
            viewModel.openExistingAccess()
        } else {
            Task { await viewModel.accept() }
        }
    }

    private var backButton: some View {
        Button {
            onFinished(
                .dismissedToHome(toastMessage: "")
            )
        } label: {
            Image(systemName: "chevron.left")
                .font(.body.weight(.semibold))
                .foregroundStyle(AppColors.primaryText)
                .frame(width: 38, height: 38)
                .background(AppColors.iconButtonBackground)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(AppColors.borderDefault, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "common.back"))
        .accessibilityIdentifier("invitation.back")
    }

    private var metadataDivider: some View {
        Rectangle()
            .fill(AppColors.borderDefault)
            .frame(height: 1)
    }

    private var declineMessageKey: LocalizedStringKey {
        switch viewModel.pendingInvitation.scope {
        case .project:
            return "invitation.decline.message.project"
        case .scan:
            return "invitation.decline.message.scan"
        }
    }

}

private struct ExpiredInvitationContent: View {
    let scope: InvitationScope
    let onBackToProjects: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: AppSpacing.small) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColors.destructiveLabel)
                    .accessibilityHidden(true)

                Text(message)
                    .appTypography(AppTypography.bodySmallStrong)
                    .foregroundStyle(AppColors.destructiveLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AppSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.destructiveSoftBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous))
            .padding(.horizontal, AppSpacing.extraLarge)
            .padding(.top, AppSpacing.medium)
            .accessibilityIdentifier("invitation.expired.banner")

            Spacer()

            PrimaryActionButton(
                title: String(localized: "invitation.expired.backToProjects"),
                systemImageName: nil,
                color: AppColors.background,
                action: onBackToProjects,
                foregroundColor: AppColors.primaryText,
                borderColor: AppColors.borderDefault,
                cornerRadius: 18,
                accessibilityIdentifier: "invitation.expired.backToProjects"
            )
            .padding(.horizontal, AppSpacing.extraLarge)
            .padding(.vertical, AppSpacing.large)
        }
    }

    private var message: String {
        switch scope {
        case .project:
            return String(localized: "invitation.expired.message.project")
        case .scan:
            return String(localized: "invitation.expired.message.scan")
        }
    }
}

private extension InvitationView {
    var blockingAlertTitle: String {
        switch viewModel.blockingAlert {
        case .alreadyAccepted:
            return String(localized: "invitation.alert.alreadyAccepted.title")
        case .declined:
            return String(localized: "invitation.alert.declined.title")
        case .expired:
            return String(localized: "invitation.alert.expired.title")
        case .unavailable:
            return String(localized: "invitation.alert.unavailable.title")
        case .accessDenied:
            return String(localized: "invitation.alert.accessDenied.title")
        case .none:
            return ""
        }
    }

    var blockingAlertMessage: String {
        switch viewModel.blockingAlert {
        case .alreadyAccepted:
            return String(localized: "invitation.alert.alreadyAccepted.message")
        case .declined:
            return String(localized: "invitation.alert.declined.message")
        case .expired:
            return String(localized: "invitation.alert.expired.message")
        case .unavailable:
            return String(localized: "invitation.alert.unavailable.message")
        case .accessDenied:
            return String(localized: "invitation.alert.accessDenied.message")
        case .none:
            return ""
        }
    }

    func loadFailedMessage(for error: InvitationServiceError) -> String {
        switch error {
        case .network:
            return String(localized: "invitation.loadFailed.network")
        case .notFound:
            return String(localized: "invitation.loadFailed.notFound")
        case .alreadyAccepted, .declined, .expired, .unavailable, .accessDenied:
            return String(localized: "invitation.loadFailed.generic")
        }
    }

    var actionFailureMessage: String {
        guard let error = viewModel.actionFailure?.error else { return "" }
        return loadFailedMessage(for: error)
    }
}

private struct InvitationThumbnailView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                .fill(
                    LinearGradient(
                        colors: [
                            AppColors.brandPrimary.opacity(0.16),
                            AppColors.noteGreen.opacity(0.16),
                            AppColors.badgeNeutralBackground
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
        .frame(height: 150)
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                .stroke(AppColors.borderStrong, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
    }
}

private struct InvitationMetadataRow: View {
    let title: String
    let value: String
    let accessibilityIdentifier: String

    var body: some View {
        HStack {
            Text(title)
                .appTypography(AppTypography.bodySmall)
                .foregroundStyle(AppColors.secondaryText)

            Spacer(minLength: AppSpacing.medium)

            Text(value)
                .appTypography(AppTypography.bodySmallStrong)
                .foregroundStyle(AppColors.primaryText)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
        .padding(.vertical, AppSpacing.medium)
    }
}

private struct InvitationAccessRow: View {
    var body: some View {
        HStack {
            Text("invitation.metadata.access")
                .appTypography(AppTypography.bodySmall)
                .foregroundStyle(AppColors.secondaryText)

            Spacer(minLength: AppSpacing.medium)

            HStack(spacing: 6) {
                Circle()
                    .fill(AppColors.secondaryText)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)

                Text("invitation.access.viewOnly")
                    .appTypography(AppTypography.labelBadge)
                    .foregroundStyle(AppColors.secondaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, AppSpacing.extraSmall)
            .background(AppColors.badgeNeutralBackground)
            .clipShape(Capsule())
            .accessibilityIdentifier("invitation.access.badge")
        }
        .padding(.vertical, AppSpacing.medium)
    }
}

#Preview("Project Invitation") {
    InvitationView(
        viewModel: InvitationViewModel(
            pendingInvitation: PendingInvitation(scope: .project, token: "valid-project"),
            service: LocalInvitationService(simulatedDelayNanoseconds: 0),
            currentUserEmail: "viewer@example.com"
        ),
        onFinished: { _ in }
    )
}
