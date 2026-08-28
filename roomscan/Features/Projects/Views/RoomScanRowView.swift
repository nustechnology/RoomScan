//
//  RoomScanRowView.swift
//  roomscan
//

import SwiftUI

struct RoomScanRowView: View {
    let scan: RoomScanSummary
    var searchQuery: String = ""
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 14) {
                ThumbnailView(thumbnailPath: scan.thumbnailPath)
                    .frame(width: 104, height: 82)

                VStack(alignment: .leading, spacing: 4) {
                    highlightedText(scan.name, query: searchQuery)
                        .font(.headline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    TimelineView(.yearBoundary) { context in
                        Text(scanMetadataText(now: context.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    ScanSyncStatusBadge(syncStatus: scan.syncStatus)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("projects.scan.\(scan.id)")
    }

    private func scanMetadataText(now: Date) -> String {
        let notesText = String.localizedStringWithFormat(
            String(localized: "projects.scan.notes.format"),
            scan.noteCount
        )
        let dateText = ProjectDateFormatting.relativeText(scan.createdAt, now: now)
        return "\(notesText) · \(dateText)"
    }
}

private struct ThumbnailView: View {
    let thumbnailPath: String

    @State private var loadedImage: UIImage?

    private static let thumbnailWidth: CGFloat = 104
    private static let thumbnailHeight: CGFloat = 82
    var body: some View {
        Group {
            if let loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("ScanThumbnail")
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: Self.thumbnailWidth, height: Self.thumbnailHeight)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
        .task(id: thumbnailPath) {
            loadedImage = nil
            let image = await ScanThumbnailLoader.load(
                from: thumbnailPath,
                maxPixelSize: Self.thumbnailMaxPixelSize
            )
            guard !Task.isCancelled else { return }
            loadedImage = image
        }
    }

    private static var thumbnailMaxPixelSize: Int {
        Int(max(thumbnailWidth, thumbnailHeight) * UIScreen.main.scale)
    }

}
