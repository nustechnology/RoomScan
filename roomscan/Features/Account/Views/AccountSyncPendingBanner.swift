//
//  AccountSyncPendingBanner.swift
//  roomscan
//

import SwiftUI

struct AccountSyncPendingBanner: View {
    let pendingCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            VStack(alignment: .leading, spacing: AppSpacing.extraSmall) {
                Text("account.sync.pending.title")
                    .appTypography(AppTypography.headingSmall)
                    .foregroundStyle(AppColors.primaryText)

                Text(
                    String.localizedStringWithFormat(
                        String(localized: "account.sync.pending.body"),
                        pendingCount
                    )
                )
                .appTypography(AppTypography.bodySmall)
                .foregroundStyle(AppColors.secondaryText)
            }

            Spacer(minLength: AppSpacing.small)

            Text("account.sync.pending.actionNeeded")
                .appTypography(AppTypography.bodySmallStrong)
                .foregroundStyle(AppColors.warningAction)
                .multilineTextAlignment(.trailing)
        }
        .padding(AppSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous)
                .fill(AppColors.warningBannerBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous)
                .stroke(AppColors.warningBannerBorder)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("account.syncPendingBanner")
    }
}
