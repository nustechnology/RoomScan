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
            scan.noteCount
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
    /// Reject oversized remote payloads before full decode.
    private static let maxRemoteThumbnailBytes = 1_500_000

    private static let thumbnailSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

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
            loadedImage = nil
            let image = await Self.loadThumbnail(
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

    nonisolated private static func loadThumbnail(
        from relativePath: String,
        maxPixelSize: Int
    ) async -> UIImage? {
        guard !relativePath.isEmpty else { return nil }

        if let remoteURL = URL(string: relativePath),
           let scheme = remoteURL.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return await loadRemoteThumbnail(from: remoteURL, maxPixelSize: maxPixelSize)
        }

        return loadLocalThumbnail(relativePath: relativePath, maxPixelSize: maxPixelSize)
    }

    nonisolated private static func loadRemoteThumbnail(
        from url: URL,
        maxPixelSize: Int
    ) async -> UIImage? {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let (bytes, response) = try await thumbnailSession.bytes(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                bytes.task.cancel()
                return nil
            }

            let expectedLength = response.expectedContentLength
            if expectedLength > Int64(maxRemoteThumbnailBytes) {
                bytes.task.cancel()
                return nil
            }

            var data = Data()
            if expectedLength > 0 {
                data.reserveCapacity(Int(expectedLength))
            }

            for try await byte in bytes {
                try Task.checkCancellation()
                data.append(byte)
                if data.count > maxRemoteThumbnailBytes {
                    bytes.task.cancel()
                    return nil
                }
            }

            return makeThumbnailImage(from: data as CFData, maxPixelSize: maxPixelSize)
        } catch is CancellationError {
            return nil
        } catch {
            return nil
        }
    }

    nonisolated private static func loadLocalThumbnail(
        relativePath: String,
        maxPixelSize: Int
    ) -> UIImage? {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsDir.appendingPathComponent(relativePath)
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
        return makeThumbnailImage(from: source, maxPixelSize: maxPixelSize)
    }

    nonisolated private static func makeThumbnailImage(
        from data: CFData,
        maxPixelSize: Int
    ) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data, nil) else { return nil }
        return makeThumbnailImage(from: source, maxPixelSize: maxPixelSize)
    }

    nonisolated private static func makeThumbnailImage(
        from source: CGImageSource,
        maxPixelSize: Int
    ) -> UIImage? {
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
