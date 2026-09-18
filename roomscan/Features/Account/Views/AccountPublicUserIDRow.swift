//
//  AccountPublicUserIDRow.swift
//  roomscan
//

import SwiftUI

struct AccountPublicUserIDRow: View {
    let publicUserID: String
    let onCopy: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            VStack(alignment: .leading, spacing: AppSpacing.extraSmall) {
                Text("account.publicUserId")
                    .appTypography(AppTypography.bodyLarge)
                    .foregroundStyle(AppColors.secondaryText)

                Text(publicUserID)
                    .appTypography(AppTypography.bodyLargeStrong)
                    .foregroundStyle(AppColors.primaryText)
                    .lineLimit(1)
                    .accessibilityIdentifier("account.publicUserId")
            }

            Spacer(minLength: 0)

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "account.publicUserId.copy"))
            .accessibilityIdentifier("account.publicUserId.copy")
        }
        .padding(.horizontal, AppSpacing.large)
        .padding(.vertical, AppSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous)
                .fill(AppColors.background)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous)
                .stroke(.quaternary)
        }
        .accessibilityIdentifier("account.publicUserIdRow")
    }
}

#Preview {
    AccountPublicUserIDRow(publicUserID: "APPLEUSER1", onCopy: {})
        .padding()
}
