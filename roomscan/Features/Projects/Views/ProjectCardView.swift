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
    let onToggleExpansion: () -> Void
    let onRoomTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if project.roomScans.isEmpty {
                EmptyRoomScansView()
            } else {
                roomScanList
            }
            expandButton
        }
        .padding(14)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
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
                Button(String(localized: "projects.card.menu.viewDetail")) {}
                Button(String(localized: "projects.card.menu.rename")) {}
                Button(String(localized: "projects.card.menu.delete"), role: .destructive) {}
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
                RoomScanRowView(scan: scan, onTap: onRoomTap)
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
    var body: some View {
        Text("projects.card.emptyScans")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .accessibilityIdentifier("projects.card.emptyScans")
    }
}
