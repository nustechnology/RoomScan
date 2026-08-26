//
//  AccountProfileCard.swift
//  roomscan
//

import SwiftUI

struct AccountProfileCard: View {
    let session: AuthenticationSession
    let onEditDisplayName: () -> Void

    private var displayName: String {
        AccountDisplayName.resolved(from: session.user.displayName)
    }

    private var initials: String {
        AccountDisplayName.initials(from: session.user.displayName)
    }

    private var subtitle: String {
        let email = session.user.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !email.isEmpty {
            return email
        }
        return session.provider.signedInSubtitle
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

                Text(subtitle)
                    .appTypography(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)
                    .accessibilityIdentifier("account.signedInProvider")
            }

            Spacer(minLength: 0)

            Button(action: onEditDisplayName) {
                Image(systemName: "pencil")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "account.editName.title"))
            .accessibilityIdentifier("account.editDisplayName")
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
        .accessibilityIdentifier("account.profileCard")
    }
}
