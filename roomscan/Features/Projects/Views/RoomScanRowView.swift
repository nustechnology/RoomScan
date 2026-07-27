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
                ThumbnailView()
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
    var body: some View {
        Image("ScanThumbnail")
            .resizable()
            .scaledToFill()
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }
}

