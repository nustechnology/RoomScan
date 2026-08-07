//
//  RoomScanRowView.swift
//  roomscan
//

import ImageIO
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

                    Text(scanMetadataText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    ScanSyncStatusBadge(syncStatus: scan.syncStatus)
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
        let dateText = RoomScanRowPresentation.dateText(scan.createdAt)
        return "\(notesText) · \(dateText)"
    }
}

private enum RoomScanRowPresentation {
    static func dateText(
        _ date: Date,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        var baseStyle = Date.FormatStyle()
            .month(.abbreviated)
            .day()
            .locale(locale)
        baseStyle.calendar = calendar
        baseStyle.timeZone = calendar.timeZone

        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(baseStyle)
        }

        return date.formatted(baseStyle.year())
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
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image("ScanThumbnail")
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .accessibilityHidden(true)
        .task(id: thumbnailPath) {
            let path = thumbnailPath
            let maxPixelSize = Self.thumbnailMaxPixelSize
            let image = await Task.detached(priority: .userInitiated) {
                Self.loadThumbnail(from: path, maxPixelSize: maxPixelSize)
            }.value
            guard !Task.isCancelled else { return }
            loadedImage = image
        }
    }

    private static var thumbnailMaxPixelSize: Int {
        Int(max(thumbnailWidth, thumbnailHeight) * UIScreen.main.scale)
    }

    nonisolated private static func loadThumbnail(
        from relativePath: String,
        maxPixelSize: Int
    ) -> UIImage? {
        guard !relativePath.isEmpty else { return nil }
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = documentsDir.appendingPathComponent(relativePath)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
