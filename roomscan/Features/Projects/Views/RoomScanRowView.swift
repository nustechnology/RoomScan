//
//  RoomScanRowView.swift
//  roomscan
//

import SwiftUI

struct RoomScanRowView: View {
    let scan: RoomScanSummary
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 14) {
                ThumbnailView()
                    .frame(width: 104, height: 82)

                VStack(alignment: .leading, spacing: 4) {
                    Text(scan.name)
                        .font(.headline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(scanMetadataText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    StatusChipView(syncStatus: scan.syncStatus)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("projects.scan.\(scan.id)")
    }

    private var scanMetadataText: String {
        let notesText = String.localizedStringWithFormat(
            String(localized: "projects.scan.notes.format"),
            scan.notes.count
        )
        let dateText = scan.createdAt.formatted(.dateTime.month(.abbreviated).day())
        return "\(notesText) · \(dateText)"
    }
}

private struct ThumbnailView: View {
    var body: some View {
        Image("ScanThumbnail")
            .resizable()
            .scaledToFill()
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }
}

private struct StatusChipView: View {
    let syncStatus: RoomScanSyncStatus

    var body: some View {
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
    }
}

private extension RoomScanSyncStatus {
    var badgeForegroundColor: Color {
        switch self {
        case .synced:
            return .green
        case .uploading:
            return .brown
        case .failed:
            return .red
        }
    }

    var badgeBackgroundColor: Color {
        if self == .uploading {
            return .yellow.opacity(0.26)
        }

        return badgeForegroundColor.opacity(0.16)
    }
}
