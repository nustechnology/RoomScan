//
//  AccountMetricsList.swift
//  roomscan
//

import SwiftUI

struct AccountMetricsList: View {
    let metrics: AccountMetrics

    var body: some View {
        VStack(spacing: 0) {
            metricRow(
                labelKey: "account.metrics.localScans",
                value: "\(metrics.localScanCount)",
                accessibilityIdentifier: "account.metrics.localScans"
            )

            Divider()

            metricRow(
                labelKey: "account.metrics.sharedProjects",
                value: "\(metrics.sharedProjectCount)",
                accessibilityIdentifier: "account.metrics.sharedProjects"
            )

            Divider()

            metricRow(
                labelKey: "account.metrics.storageUsed",
                value: metrics.formattedStorageUsed,
                accessibilityIdentifier: "account.metrics.storageUsed"
            )
        }
        .padding(.horizontal, AppSpacing.large)
        .background(AppColors.background)
        .accessibilityIdentifier("account.metricsList")
    }

    private func metricRow(
        labelKey: LocalizedStringKey,
        value: String,
        accessibilityIdentifier: String
    ) -> some View {
        HStack {
            Text(labelKey)
                .appTypography(AppTypography.bodyLarge)
                .foregroundStyle(AppColors.secondaryText)

            Spacer()

            Text(value)
                .appTypography(AppTypography.bodyLargeStrong)
                .foregroundStyle(AppColors.primaryText)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
        .padding(.vertical, AppSpacing.large)
        .accessibilityElement(children: .combine)
    }
}
