//
//  MemberActionsBottomSheet.swift
//  roomscan
//

import SwiftUI

struct MemberActionsBottomSheet: View {
    let member: InvitedMember
    let performingAction: ShareMemberAction?
    let onResendInvitation: () -> Void
    let onCancelInvitation: () -> Void
    let onRemoveAccess: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.extraLarge) {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text(titleText)
                        .appTypography(AppTypography.headingLarge)
                        .foregroundStyle(AppColors.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(subtitleText)
                        .appTypography(AppTypography.bodyMedium)
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(spacing: AppSpacing.medium) {
                    ForEach(actions) { action in
                        let isLoading = action.kind != nil && action.kind == performingAction
                        PrimaryActionButton(
                            title: action.title,
                            systemImageName: nil,
                            color: AppColors.background,
                            action: action.handler,
                            foregroundColor: action.isDestructive ? AppColors.error : AppColors.primaryText,
                            borderColor: action.isDestructive ? AppColors.error : Color(uiColor: .systemGray4),
                            borderWidth: 1.5,
                            cornerRadius: AppCornerRadius.large,
                            isLoading: isLoading,
                            accessibilityIdentifier: action.accessibilityIdentifier
                        )
                        .accessibilityLabel(isLoading ? action.loadingTitle : action.title)
                        .opacity(isBusy && !isLoading ? 0.6 : 1)
                        .allowsHitTesting(!isBusy)
                    }
                }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, AppSpacing.extraLarge)
                .padding(.top, AppSpacing.extraLarge)
                .padding(.bottom, AppSpacing.large)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(AppColors.background)
        }
        .background(AppColors.background)
        .presentationBackground(AppColors.background)
        .presentationDetents(member.status == .accepted ? [.fraction(0.36)] : [.fraction(0.44)])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isBusy)
    }

    private var isBusy: Bool {
        performingAction != nil
    }

    private var titleText: String {
        member.rowTitle
    }

    private var subtitleText: String {
        member.subtitle
    }

    private var actions: [MemberAction] {
        switch member.status {
        case .accepted:
            return [
                MemberAction(
                    kind: .removeAccess,
                    title: String(localized: "share.member.removeAccess"),
                    loadingTitle: String(localized: "share.member.removeAccess.loading"),
                    isDestructive: true,
                    accessibilityIdentifier: "share.member.removeAccess",
                    handler: onRemoveAccess
                ),
                MemberAction(
                    kind: nil,
                    title: String(localized: "share.member.cancel"),
                    loadingTitle: String(localized: "share.member.cancel"),
                    isDestructive: false,
                    accessibilityIdentifier: "share.member.cancel",
                    handler: onCancel
                )
            ]
        case .pending:
            return [
                MemberAction(
                    kind: .resendInvitation,
                    title: String(localized: "share.member.resendInvitation"),
                    loadingTitle: String(localized: "share.member.resendInvitation.loading"),
                    isDestructive: false,
                    accessibilityIdentifier: "share.member.resendInvitation",
                    handler: onResendInvitation
                ),
                MemberAction(
                    kind: .cancelInvitation,
                    title: String(localized: "share.member.cancelInvitation"),
                    loadingTitle: String(localized: "share.member.cancelInvitation.loading"),
                    isDestructive: true,
                    accessibilityIdentifier: "share.member.cancelInvitation",
                    handler: onCancelInvitation
                ),
                MemberAction(
                    kind: nil,
                    title: String(localized: "share.member.cancel"),
                    loadingTitle: String(localized: "share.member.cancel"),
                    isDestructive: false,
                    accessibilityIdentifier: "share.member.cancel",
                    handler: onCancel
                )
            ]
        }
    }
}

private struct MemberAction: Identifiable {
    var id: String { accessibilityIdentifier }
    let kind: ShareMemberAction?
    let title: String
    let loadingTitle: String
    let isDestructive: Bool
    let accessibilityIdentifier: String
    let handler: () -> Void
}
