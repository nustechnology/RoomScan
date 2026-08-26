//
//  ScanSyncStatusBadge.swift
//  roomscan
//

import SwiftUI

struct ScanSyncStatusBadge: View {
    let syncStatus: RoomScanSyncStatus
    var showsRetry: Bool = false
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                Circle()
                    .fill(syncStatus.badgeForegroundColor)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)

                Text(syncStatus.localizedTitle)
                    .font(.system(size: 12, weight: .black))
                    .lineLimit(1)
            }
            .foregroundStyle(syncStatus.badgeForegroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(syncStatus.badgeBackgroundColor)
            .clipShape(Capsule())
            .accessibilityIdentifier("projects.scan.status.\(syncStatus.rawValue)")

            if showsRetry, let onRetry {
                Button(action: onRetry) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(syncStatus.badgeForegroundColor)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "scanDetail.status.retry.accessibility"))
                .accessibilityIdentifier("scanDetail.status.retry")
            }
        }
    }
}

extension RoomScanSyncStatus {
    var badgeForegroundColor: Color {
        switch self {
        case .pending:
            return .orange
        case .synced:
            return .green
        case .uploading:
            return .brown
        case .failed, .conflict:
            return .red
        }
    }

    var badgeBackgroundColor: Color {
        if self == .uploading {
            return .yellow.opacity(0.26)
        }
        if self == .pending {
            return Color.orange.opacity(0.16)
        }

        return badgeForegroundColor.opacity(0.16)
    }
}
