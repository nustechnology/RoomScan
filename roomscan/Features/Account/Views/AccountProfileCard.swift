//
//  AccountProfileCard.swift
//  roomscan
//

import SwiftUI

struct AccountProfileCard: View {
    let session: AuthenticationSession

    private var displayName: String {
        AccountDisplayName.resolved(from: session.user.displayName)
    }

    private var initials: String {
        AccountDisplayName.initials(from: session.user.displayName)
    }

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            Text(initials)
                .appTypography(AppTypography.headingMedium)
                .foregroundStyle(AppColors.avatarPlaceholderForeground)
                .frame(width: 56, height: 56)
                .background(AppColors.avatarPlaceholderBackground, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppSpacing.extraSmall) {
                Text(displayName)
                    .appTypography(AppTypography.headingSmall)
                    .foregroundStyle(AppColors.primaryText)
                    .lineLimit(1)
                    .accessibilityIdentifier("account.displayName")

                Text(session.provider.signedInSubtitle)
                    .appTypography(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)
                    .accessibilityIdentifier("account.signedInProvider")
            }

            Spacer(minLength: 0)
        }
        .padding(AppSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous)
                .fill(AppColors.background)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous)
                .stroke(.quaternary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("account.profileCard")
    }
}
