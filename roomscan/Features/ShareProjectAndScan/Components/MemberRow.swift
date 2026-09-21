//
//  MemberRow.swift
//  roomscan
//

import SwiftUI

struct MemberRow: View {
    let member: InvitedMember
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.medium) {
                avatar

                VStack(alignment: .leading, spacing: AppSpacing.extraSmall) {
                    Text(member.rowTitle)
                        .appTypography(AppTypography.bodyMediumStrong)
                        .foregroundStyle(AppColors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let publicUserIdLabel = member.publicUserIdLabel {
                        Text(publicUserIdLabel)
                            .appTypography(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("share.member.publicUserId")
                    }

                    Text(member.subtitle)
                        .appTypography(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                StatusBadge(status: member.status)

                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppColors.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(AppSpacing.large)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(AppColors.background)
        .accessibilityIdentifier("share.member.\(member.id)")
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(Color.primary.opacity(0.08))

            Text(member.initials)
                .appTypography(AppTypography.bodySmallStrong)
                .foregroundStyle(AppColors.primaryText)
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}
