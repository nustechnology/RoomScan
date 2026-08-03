//
//  SharedScanCardView.swift
//  roomscan
//

import SwiftUI

struct SharedScanCardView: View {
    let scan: SharedScanItem
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                HStack(alignment: .top, spacing: AppSpacing.medium) {
                    SharedThumbnailView(thumbnailName: scan.thumbnailName)
                        .frame(width: 88, height: 72)

                    VStack(alignment: .leading, spacing: AppSpacing.extraSmall) {
                        Text(scan.name)
                            .font(.headline.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .accessibilityIdentifier("shared.scan.title.\(scan.id)")

                        Text(ownerLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .accessibilityIdentifier("shared.scan.owner.\(scan.id)")

                        Text(projectLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .accessibilityIdentifier("shared.scan.project.\(scan.id)")

                        SharedAccessStatusBadge(status: scan.status, scope: .scan)
                    }

                    Spacer(minLength: 0)
                }

                if scan.isInactive {
                    Text(scan.status.helperText(for: .scan))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("shared.scan.helper.\(scan.id)")
                }
            }
            .padding(AppSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(String(localized: "shared.remove.action"), role: .destructive, action: onRemove)
        }
        .accessibilityIdentifier("shared.scan.card.\(scan.id)")
    }

    private var ownerLine: String {
        SharedScanCardPresentation.ownerLine(
            ownerName: scan.ownerName,
            noteCount: scan.noteCount
        )
    }

    private var projectLine: String {
        String.localizedStringWithFormat(
            String(localized: "shared.scan.project.format"),
            scan.projectName
        )
    }
}

enum SharedScanCardPresentation {
    static func ownerLine(ownerName: String, noteCount: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "shared.scan.owner.format"),
            ownerName,
            noteCount
        )
    }
}
