//
//  ShareView.swift
//  roomscan
//

import SwiftUI

struct ShareView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ShareViewModel

    init(input: ShareScreenInput, service: any ShareService) {
        _viewModel = State(
            initialValue: ShareViewModel(input: input, service: service)
        )
    }

    init(viewModel: ShareViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            content
                .background(AppColors.background)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.headline.weight(.semibold))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .foregroundStyle(.primary)
                        .accessibilityLabel(String(localized: "common.back"))
                        .accessibilityIdentifier("share.back")
                    }

                    ToolbarItem(placement: .principal) {
                        Text(viewModel.input.screenTitle)
                            .appTypography(AppTypography.headingLarge)
                            .foregroundStyle(AppColors.primaryText)
                    }
                }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.isInviteSheetPresented },
                set: { if !$0 { viewModel.closeInviteSheet() } }
            )
        ) {
            InvitePeopleBottomSheet(
                email: Binding(
                    get: { viewModel.inviteEmail },
                    set: { viewModel.updateInviteEmail($0) }
                ),
                validationMessage: viewModel.emailValidationMessage,
                permission: .viewOnly,
                isOffline: viewModel.isOffline,
                isSending: viewModel.isSendingInvite,
                isCopyingLink: viewModel.isCopyingInvitationLink,
                onSendInvite: {
                    Task {
                        await viewModel.sendInvite()
                    }
                },
                onCopyInvitationLink: {
                    Task {
                        await viewModel.copyInvitationLink()
                    }
                }
            )
        }
        .sheet(
            item: Binding(
                get: { viewModel.selectedMember },
                set: { newValue in
                    if newValue == nil {
                        viewModel.dismissActions()
                    }
                }
            )
        ) { member in
            MemberActionsBottomSheet(
                member: member,
                performingAction: viewModel.performingMemberAction,
                onResendInvitation: {
                    Task {
                        await viewModel.resendInvitation(for: member)
                    }
                },
                onCancelInvitation: {
                    Task {
                        await viewModel.cancelInvitation(for: member)
                    }
                },
                onRemoveAccess: {
                    Task {
                        await viewModel.removeAccess(for: member)
                    }
                },
                onCancel: {
                    viewModel.dismissActions()
                }
            )
        }
        .toast(message: Binding(
            get: { viewModel.toastMessage },
            set: { if $0 == nil { viewModel.dismissToast() } }
        ), style: Binding(
            get: { viewModel.toastStyle },
            set: { _ in }
        ))
        .accessibilityIdentifier("share.screen")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.viewState {
        case .idle, .loading:
            ProgressView(String(localized: "share.loading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("share.loading")

        case .failed:
            ContentUnavailableView {
                Label(String(localized: "share.error.load"), systemImage: "wifi.exclamationmark")
            } description: {
                Text(viewModel.errorMessage ?? String(localized: "share.error.tryAgain"))
            } actions: {
                Button(String(localized: "share.retry")) {
                    Task {
                        await viewModel.retryLoad()
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if viewModel.isOffline {
                    OfflineBanner()
                        .padding(.top, AppSpacing.medium)
                }
            }
            .accessibilityIdentifier("share.error")

        case .empty:
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    header

                    EmptyStateView(
                        title: viewModel.input.emptyStateTitle,
                        message: viewModel.input.emptyStateMessage,
                        actionTitle: String(localized: "share.invite.title"),
                        isActionEnabled: viewModel.canInvitePeople,
                        action: { viewModel.openInviteSheet() }
                    )
                    .frame(minHeight: 420)
                }
                .padding(.horizontal, AppSpacing.extraLarge)
                .padding(.top, AppSpacing.small)
                .padding(.bottom, AppSpacing.large)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if viewModel.isOffline {
                    OfflineBanner()
                        .padding(.top, AppSpacing.medium)
                        .padding(.horizontal, AppSpacing.extraLarge)
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .accessibilityIdentifier("share.empty")

        case .loaded:
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    header

                    Text(viewModel.invitedPeopleTitle)
                        .appTypography(AppTypography.labelField)
                        .foregroundStyle(AppColors.secondaryText)
                        .accessibilityIdentifier("share.invitedPeople.title")

                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.members) { member in
                            MemberRow(member: member) {
                                viewModel.presentActions(for: member)
                            }

                            if member.id != viewModel.members.last?.id {
                                Divider()
                                    .padding(.leading, 72)
                            }
                        }
                    }
                    .background(AppColors.background)
                    .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                }
                .padding(.horizontal, AppSpacing.extraLarge)
                .padding(.top, AppSpacing.small)
                .padding(.bottom, AppSpacing.large)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if viewModel.isOffline {
                    OfflineBanner()
                        .padding(.top, AppSpacing.medium)
                        .padding(.horizontal, AppSpacing.extraLarge)
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(
                    title: String(localized: "share.invite.title"),
                    systemImageName: "person.badge.plus",
                    color: AppColors.brandBlueBottom,
                    action: { viewModel.openInviteSheet() },
                    foregroundColor: AppColors.primaryActionLabel,
                    cornerRadius: AppCornerRadius.medium,
                    accessibilityIdentifier: "share.invite"
                )
                .disabled(!viewModel.canInvitePeople)
                .opacity(viewModel.canInvitePeople ? 1 : 0.6)
                .padding(.horizontal, AppSpacing.extraLarge)
                .padding(.top, AppSpacing.medium)
                .padding(.bottom, AppSpacing.large)
                .background(AppColors.background)
            }
            .accessibilityIdentifier("share.loaded")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(viewModel.input.titleText)
                .appTypography(AppTypography.headingLarge)
                .foregroundStyle(AppColors.primaryText)

            Text(viewModel.input.descriptionText)
                .appTypography(AppTypography.bodyMedium)
                .foregroundStyle(AppColors.secondaryText)
        }
    }

}

private struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(AppColors.noteOrange)

            Text(String(localized: "share.offline.actionsUnavailable"))
                .appTypography(AppTypography.bodySmallStrong)
                .foregroundStyle(AppColors.primaryText)

            Spacer()
        }
        .padding(.horizontal, AppSpacing.medium)
        .padding(.vertical, AppSpacing.small)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous))
        .accessibilityIdentifier("share.offlineBanner")
    }
}

#Preview("Project") {
    ShareView(
        input: .project(id: "project-1", name: "Lakeside Remodel", hasUploadedScan: true),
        service: MockShareService()
    )
}

#Preview("Scan Empty") {
    ShareView(
        input: .scan(
            projectID: "project-1",
            projectName: "Lakeside Remodel",
            scanID: "scan-1",
            scanName: "Living Room",
            syncStatus: .synced
        ),
        service: MockShareService(scenario: .empty, simulatedDelayNanoseconds: 0)
    )
}

#Preview("Offline") {
    ShareView(
        input: .project(id: "project-1", name: "Lakeside Remodel", hasUploadedScan: true),
        service: MockShareService(scenario: .offline, simulatedDelayNanoseconds: 0)
    )
}
