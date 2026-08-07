//
//  ProjectCardView.swift
//  roomscan
//

import SwiftUI

struct ProjectCardView: View {
    let project: ProjectSummary
    let visibleRoomScans: [RoomScanSummary]
    let isExpanded: Bool
    let showsExpandControl: Bool
    var searchQuery: String = ""
    let onProjectTap: () -> Void
    let onShare: () -> Void
    let onToggleExpansion: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    var onRoomTap: (RoomScanSummary) -> Void = { _ in }
    var onAddScan: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if project.roomScans.isEmpty {
                EmptyRoomScansView(onTap: onAddScan)
            } else {
                roomScanList
            }
            expandButton
        }
        .padding(14)
        .background {
            Button(action: onProjectTap) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.background)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(project.name)
            .accessibilityIdentifier("projects.card.open.\(project.id)")
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: onProjectTap)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                highlightedText(project.name, query: searchQuery)
                    .font(.title2.bold())
                    .lineLimit(1)
                    .accessibilityIdentifier("projects.card.title.\(project.id)")

                Text(scanCountText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("projects.card.scanCount.\(project.id)")
            }

            Spacer()

            Menu {
                Button(String(localized: "projects.card.menu.share"), action: onShare)
                Button(String(localized: "projects.card.menu.edit"), action: onEdit)
                Button(String(localized: "projects.card.menu.delete"), role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(String(localized: "projects.card.menu.accessibility"))
            .accessibilityIdentifier("projects.card.menu.\(project.id)")
        }
    }

    private var roomScanList: some View {
        VStack(spacing: 10) {
            ForEach(visibleRoomScans) { scan in
                RoomScanRowView(
                    scan: scan,
                    searchQuery: searchQuery,
                    onTap: { onRoomTap(scan) }
                )
            }
        }
    }

    @ViewBuilder
    private var expandButton: some View {
        if showsExpandControl {
            Button(action: onToggleExpansion) {
                Label(expandButtonTitle, systemImage: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .accessibilityIdentifier("projects.card.expand.\(project.id)")
        }
    }

    private var scanCountText: String {
        String.localizedStringWithFormat(
            String(localized: "projects.card.scanCount.format"),
            project.roomScans.count
        )
    }

    private var expandButtonTitle: String {
        if isExpanded {
            return String(localized: "projects.card.showLess")
        }

        let remainingCount = project.roomScans.count - visibleRoomScans.count
        return String.localizedStringWithFormat(
            String(localized: "projects.card.showMore.format"),
            remainingCount
        )
    }
}

private struct EmptyRoomScansView: View {
    var onTap: (() -> Void)?

    var body: some View {
        if let onTap {
            Button(action: onTap) {
                content
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("projects.card.emptyScans")
        } else {
            content
                .accessibilityIdentifier("projects.card.emptyScans")
        }
    }

    private var content: some View {
        Text("projects.card.emptyScans")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }
}

func highlightedText(_ text: String, query: String) -> Text {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else { return Text(text) }

    let lowercasedText = text.localizedLowercase
    let lowercasedQuery = trimmedQuery.localizedLowercase
    guard let range = lowercasedText.range(of: lowercasedQuery) else {
        return Text(text)
    }

    let startOffset = lowercasedText.distance(from: lowercasedText.startIndex, to: range.lowerBound)
    let endOffset = lowercasedText.distance(from: lowercasedText.startIndex, to: range.upperBound)
    let start = text.index(text.startIndex, offsetBy: startOffset)
    let end = text.index(text.startIndex, offsetBy: endOffset)

    let prefix = String(text[..<start])
    let match = String(text[start..<end])
    let suffix = String(text[end...])

    return Text(prefix)
        + Text(match).foregroundStyle(.blue)
        + Text(suffix)
}
