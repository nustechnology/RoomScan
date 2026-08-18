//
//  NotesListSection.swift
//  roomscan
//

import SwiftUI

struct NotesListSection: View {
    let notes: [SpatialNote]
    let selectedNoteID: String?
    let isLoading: Bool
    let isAddEnabled: Bool
    let showsOwnerActions: Bool
    let onAddNote: () -> Void
    let onSelectNote: (SpatialNote) -> Void
    let onEditNote: (SpatialNote) -> Void
    let onMoveNote: (SpatialNote) -> Void
    let onDeleteNote: (SpatialNote) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("viewer.notes.title")
                    .appTypography(AppTypography.headingSmall)
                    .foregroundStyle(AppColors.primaryText)

                Spacer()

                if showsOwnerActions {
                    Button(action: onAddNote) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.caption.weight(.bold))
                            Text("viewer.notes.add")
                                .appTypography(AppTypography.bodySmallStrong)
                        }
                        .foregroundStyle(AppColors.brandBlueBottom)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppColors.brandBlueBottom.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isAddEnabled || isLoading)
                    .opacity(isAddEnabled && !isLoading ? 1 : 0.45)
                    .accessibilityIdentifier("viewer.notes.add")
                }
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.top, AppSpacing.large)
            .padding(.bottom, AppSpacing.medium)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppSpacing.large)
                    .padding(.bottom, AppSpacing.large)
                    .accessibilityIdentifier("viewer.notes.loading")
            } else if notes.isEmpty {
                Text("viewer.notes.empty")
                    .appTypography(AppTypography.bodyMedium)
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppSpacing.large)
                    .padding(.bottom, AppSpacing.large)
                    .accessibilityIdentifier("viewer.notes.empty")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(notes) { note in
                            NoteRowView(
                                note: note,
                                isSelected: note.id == selectedNoteID,
                                showsOwnerActions: showsOwnerActions,
                                onTap: { onSelectNote(note) },
                                onEdit: { onEditNote(note) },
                                onMove: { onMoveNote(note) },
                                onDelete: { onDeleteNote(note) }
                            )

                            if note.id != notes.last?.id {
                                Divider()
                                    .padding(.leading, AppSpacing.large + 22 + AppSpacing.medium)
                            }
                        }
                    }
                }
                .padding(.bottom, AppSpacing.small)
            }
        }
        .disabled(isLoading)
        .background(AppColors.background)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .accessibilityIdentifier("viewer.notes.section")
    }
}
