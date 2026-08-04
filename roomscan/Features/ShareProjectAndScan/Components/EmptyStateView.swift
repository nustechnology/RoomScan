//
//  EmptyStateView.swift
//  roomscan
//

import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    let actionTitle: String
    let isActionEnabled: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.large) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText)

            VStack(spacing: AppSpacing.small) {
                Text(title)
                    .appTypography(AppTypography.headingMedium)
                    .foregroundStyle(AppColors.primaryText)
                    .multilineTextAlignment(.center)

                Text(message)
                    .appTypography(AppTypography.bodyMedium)
                    .foregroundStyle(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
            }

            PrimaryActionButton(
                title: actionTitle,
                systemImageName: "person.badge.plus",
                color: AppColors.brandBlueBottom,
                action: action,
                foregroundColor: AppColors.primaryActionLabel,
                cornerRadius: AppCornerRadius.medium,
                accessibilityIdentifier: "share.empty.invite"
            )
            .disabled(!isActionEnabled)
            .opacity(isActionEnabled ? 1 : 0.6)
        }
        .padding(AppSpacing.extraLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
