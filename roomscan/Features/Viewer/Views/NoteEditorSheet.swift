//
//  NoteEditorSheet.swift
//  roomscan
//

import SwiftUI

struct NoteEditorSheet: View {
    private enum Field: Hashable {
        case title
        case description
    }

    @State private var viewModel: NoteEditorViewModel
    @FocusState private var focusedField: Field?
    // `@MainActor` required: without it, Approachable Concurrency miscompiles async
    // closure ABI and the first String arg becomes the isolation token (crash in createNote).
    let onSave: @MainActor (String, String, NoteColor) async -> Bool
    let onCancel: () -> Void

    init(
        mode: NoteEditorMode,
        onSave: @escaping @MainActor (String, String, NoteColor) async -> Bool,
        onCancel: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: NoteEditorViewModel(mode: mode))
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.extraLarge) {
                    titleField
                    descriptionField
                    colorPicker

                    if let validationMessage = viewModel.validationMessage {
                        Text(validationMessage)
                            .foregroundStyle(AppColors.error)
                            .appTypography(AppTypography.bodySmall)
                    }
                }
                .padding(.horizontal, AppSpacing.extraLarge)
                .padding(.top, AppSpacing.extraLarge)
                .padding(.bottom, AppSpacing.extraLarge)
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { focusedField = nil }
                }
            }
            .scrollDismissesKeyboard(.interactively)

            actions
        }
        .background(AppColors.background)
        .interactiveDismissDisabled(viewModel.isSaving)
        .disabled(viewModel.isSaving)
    }

    private var header: some View {
        ZStack {
            Text(navigationTitle)
                .appTypography(AppTypography.headingLarge)
                .foregroundStyle(AppColors.primaryText)
                .lineLimit(1)

            HStack {
                Button(action: onCancel) {
                    Image(systemName: "chevron.left")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(AppColors.primaryText)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .background(.quaternary.opacity(0.45), in: Circle())
                .disabled(viewModel.isSaving)
                .accessibilityLabel(String(localized: "common.back"))
                .accessibilityIdentifier("viewer.note.editor.back")

                Spacer()
            }
        }
        .padding(.horizontal, AppSpacing.extraLarge)
        .padding(.top, AppSpacing.small)
        .padding(.bottom, AppSpacing.medium)
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("viewer.note.editor.titleLabel")
                .appTypography(AppTypography.headingSmall)
                .foregroundStyle(AppColors.secondaryText)

            TextField(
                String(localized: "viewer.note.editor.titlePlaceholder"),
                text: Binding(
                    get: { viewModel.title },
                    set: { viewModel.updateTitle($0) }
                )
            )
            .textFieldStyle(.plain)
            .appTypography(AppTypography.bodyLarge)
            .foregroundStyle(AppColors.primaryText)
            .padding(.horizontal, AppSpacing.large)
            .frame(height: 56)
            .background(AppColors.background)
            .overlay {
                RoundedRectangle(cornerRadius: AppCornerRadius.large)
                    .stroke(Color(uiColor: .systemGray4), lineWidth: 1.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large))
            .focused($focusedField, equals: .title)
            .accessibilityIdentifier("viewer.note.editor.title")

            characterCountText("\(viewModel.titleCharacterCount)/\(NoteEditorViewModel.titleLimit)")
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("viewer.note.editor.descriptionLabel")
                .appTypography(AppTypography.headingSmall)
                .foregroundStyle(AppColors.secondaryText)

            TextField(
                String(localized: "viewer.note.editor.descriptionPlaceholder"),
                text: Binding(
                    get: { viewModel.noteDescription },
                    set: { viewModel.updateDescription($0) }
                ),
                axis: .vertical
            )
            .lineLimit(4...10)
            .textFieldStyle(.plain)
            .appTypography(AppTypography.bodyLarge)
            .foregroundStyle(AppColors.primaryText)
            .padding(AppSpacing.large)
            .frame(minHeight: 132, alignment: .topLeading)
            .background(AppColors.background)
            .overlay {
                RoundedRectangle(cornerRadius: AppCornerRadius.large)
                    .stroke(Color(uiColor: .systemGray4), lineWidth: 1.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large))
            .focused($focusedField, equals: .description)
            .accessibilityIdentifier("viewer.note.editor.description")

            characterCountText(
                "\(viewModel.descriptionCharacterCount)/\(NoteEditorViewModel.descriptionLimit)"
            )
        }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text("viewer.note.editor.colorLabel")
                .appTypography(AppTypography.headingSmall)
                .foregroundStyle(AppColors.secondaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.medium) {
                    ForEach(NoteColor.allCases) { color in
                        Button {
                            viewModel.selectColor(color)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(AppColors.background)
                                    .frame(width: 50, height: 50)

                                Image(color.pinImageName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 28, height: 28)

                                if viewModel.color == color {
                                    Circle()
                                        .strokeBorder(AppColors.primaryText, lineWidth: 2.5)
                                        .frame(width: 50, height: 50)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(color.accessibilityLabel)
                        .accessibilityAddTraits(viewModel.color == color ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: AppSpacing.large) {
            PrimaryActionButton(
                title: String(localized: "viewer.note.editor.save"),
                systemImageName: nil,
                color: viewModel.canSave && !viewModel.isSaving
                    ? AppColors.brandBlueBottom
                    : Color(uiColor: .systemGray3),
                action: save,
                isLoading: viewModel.isSaving,
                accessibilityIdentifier: "viewer.note.editor.save"
            )
            .disabled(!viewModel.canSave || viewModel.isSaving)

            PrimaryActionButton(
                title: String(localized: "viewer.note.editor.cancel"),
                systemImageName: nil,
                color: AppColors.background,
                action: onCancel,
                foregroundColor: viewModel.isSaving ? AppColors.secondaryText : AppColors.primaryText,
                borderColor: Color(uiColor: .systemGray4),
                borderWidth: 1.5,
                cornerRadius: AppCornerRadius.large,
                accessibilityIdentifier: "viewer.note.editor.cancel"
            )
            .disabled(viewModel.isSaving)
        }
        .padding(.horizontal, AppSpacing.extraLarge)
        .padding(.top, AppSpacing.large)
        .padding(.bottom, AppSpacing.large)
    }

    private var navigationTitle: String {
        switch viewModel.mode {
        case .create:
            return String(localized: "viewer.note.editor.title.create")
        case .edit:
            return String(localized: "viewer.note.editor.title.edit")
        }
    }

    private func save() {
        guard let title = viewModel.validatedTitle(),
              let description = viewModel.validatedDescription() else {
            return
        }
        viewModel.setSaving(true)

        Task {
            defer { viewModel.setSaving(false) }
            let didSave = await onSave(title, description, viewModel.color)
            if !didSave {
                viewModel.reportSaveFailed()
            }
        }
    }

    private func characterCountText(_ text: String) -> some View {
        Text(text)
            .appTypography(AppTypography.captionMedium)
            .foregroundStyle(AppColors.secondaryText)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
