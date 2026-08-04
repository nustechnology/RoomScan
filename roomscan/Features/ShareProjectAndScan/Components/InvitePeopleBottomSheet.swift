//
//  InvitePeopleBottomSheet.swift
//  roomscan
//

import SwiftUI

struct InvitePeopleBottomSheet: View {
    @Binding var email: String

    let validationMessage: String?
    let permission: SharePermission
    let isOffline: Bool
    let isSending: Bool
    let isCopyingLink: Bool
    let onSendInvite: () -> Void
    let onCopyInvitationLink: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text("share.invite.email")
                        .appTypography(AppTypography.labelField)
                        .foregroundStyle(AppColors.secondaryText)

                    TextField(String(localized: "share.invite.email.placeholder"), text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .padding(.horizontal, AppSpacing.medium)
                        .padding(.vertical, AppSpacing.large)
                        .background(
                            RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous)
                                .stroke(validationMessage == nil ? Color.primary.opacity(0.14) : AppColors.error, lineWidth: 1)
                        )
                        .accessibilityIdentifier("share.invite.email")

                    if let validationMessage {
                        Text(validationMessage)
                            .appTypography(AppTypography.captionMedium)
                            .foregroundStyle(AppColors.error)
                            .accessibilityIdentifier("share.invite.validation")
                    }
                }

                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text("share.invite.permission")
                        .appTypography(AppTypography.labelField)
                        .foregroundStyle(AppColors.secondaryText)

                    HStack {
                        Text(permission.title)
                            .appTypography(AppTypography.bodyMediumStrong)
                            .foregroundStyle(AppColors.primaryText)

                        Spacer()
                    }
                    .padding(.horizontal, AppSpacing.medium)
                    .padding(.vertical, AppSpacing.large)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous))
                }

                if isOffline {
                    Text("share.invite.offline")
                        .appTypography(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.secondaryText)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(AppSpacing.extraLarge)
            .background(AppColors.background)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: AppSpacing.medium) {
                    PrimaryActionButton(
                        title: isSending
                            ? String(localized: "share.invite.sending")
                            : String(localized: "share.invite.send"),
                        systemImageName: isSending ? nil : "envelope.fill",
                        color: AppColors.brandBlueBottom,
                        action: onSendInvite,
                        foregroundColor: AppColors.primaryActionLabel,
                        cornerRadius: AppCornerRadius.medium,
                        accessibilityIdentifier: "share.invite.send"
                    )
                    .disabled(isOffline || isSending || isCopyingLink)
                    .opacity(isOffline || isSending || isCopyingLink ? 0.6 : 1)

                    Button(action: onCopyInvitationLink) {
                        HStack(spacing: AppSpacing.small) {
                            if !isCopyingLink {
                                Image(systemName: "link")
                            }
                            Text(isCopyingLink
                                ? String(localized: "share.invite.copying")
                                : String(localized: "share.invite.copyLink"))
                        }
                        .appTypography(AppTypography.bodyMediumStrong)
                        .foregroundStyle(AppColors.brandBlueBottom)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("share.invite.copyLink")
                    .disabled(isOffline || isSending || isCopyingLink)
                    .opacity(isOffline || isSending || isCopyingLink ? 0.6 : 1)
                }
                .padding(.horizontal, AppSpacing.extraLarge)
                .padding(.top, AppSpacing.medium)
                .padding(.bottom, AppSpacing.large)
                .background(AppColors.background)
            }
            .navigationTitle(String(localized: "share.invite.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .background(AppColors.background)
        }
        .background(AppColors.background)
        .presentationBackground(AppColors.background)
        .presentationDetents([.fraction(0.52)])
        .presentationDragIndicator(.visible)
    }
}
