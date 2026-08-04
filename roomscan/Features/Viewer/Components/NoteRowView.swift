//
//  NoteRowView.swift
//  roomscan
//

import SwiftUI

struct NoteRowView: View {
    let note: SpatialNote
    let isSelected: Bool
    let showsOwnerActions: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onMove: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                Image(note.color.pinImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .accessibilityLabel(note.color.accessibilityLabel)

                VStack(alignment: .leading, spacing: AppSpacing.extraSmall) {
                    Text(note.title)
                        .appTypography(AppTypography.bodyMediumStrong)
                        .foregroundStyle(AppColors.primaryText)
                        .lineLimit(1)

                    Text(note.detail)
                        .appTypography(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.vertical, AppSpacing.medium)
            .background(isSelected ? note.color.swiftUIColor.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if showsOwnerActions {
                Button(String(localized: "viewer.note.menu.edit"), action: onEdit)
                Button(String(localized: "viewer.note.menu.move"), action: onMove)
                Button(String(localized: "viewer.note.menu.delete"), role: .destructive, action: onDelete)
            }
        }
        .accessibilityIdentifier("viewer.note.row.\(note.id)")
    }
}
