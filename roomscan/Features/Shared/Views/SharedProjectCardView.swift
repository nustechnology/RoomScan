//
//  SharedProjectCardView.swift
//  roomscan
//

import SwiftUI

struct SharedProjectCardView: View {
    let project: SharedProjectItem
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                HStack(alignment: .top, spacing: AppSpacing.medium) {
                    SharedThumbnailView(thumbnailName: project.thumbnailName)
                        .frame(width: 88, height: 72)

                    VStack(alignment: .leading, spacing: AppSpacing.extraSmall) {
                        Text(SharedProjectCardPresentation.title(for: project.name))
                            .font(.headline.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .accessibilityIdentifier("shared.project.title.\(project.id)")

                        Text(subtitleText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .accessibilityIdentifier("shared.project.subtitle.\(project.id)")

                        SharedAccessStatusBadge(status: project.status, scope: .project)
                    }

                    Spacer(minLength: 0)
                }

                if project.isInactive {
                    Text(project.status.helperText(for: .project))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("shared.project.helper.\(project.id)")
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
        .accessibilityIdentifier("shared.project.card.\(project.id)")
    }

    private var subtitleText: String {
        SharedProjectCardPresentation.subtitle(
            ownerName: project.ownerName,
            scanCount: project.scanCount
        )
    }
}

enum SharedProjectCardPresentation {
    static func title(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return String(localized: "shared.project.placeholderName")
        }
        return trimmed
    }

    static func subtitle(ownerName: String, scanCount: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "shared.project.subtitle.format"),
            ownerName,
            scanCount
        )
    }
}
