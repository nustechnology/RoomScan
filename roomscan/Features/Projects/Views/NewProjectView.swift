//
//  NewProjectView.swift
//  roomscan
//

import SwiftUI

struct NewProjectView: View {
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var projectName = ""
    @State private var description = ""
    @State private var showsNameError = false
    @State private var showsDiscardAlert = false

    private enum Field {
        case name
        case description
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.extraLarge) {
                    nameField
                    descriptionField

                    Text("projects.form.helper")
                        .appTypography(AppTypography.bodyLarge)
                        .foregroundStyle(AppColors.secondaryText)
                }
                .padding(.horizontal, AppSpacing.extraLarge)
                .padding(.top, AppSpacing.extraLarge)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = nil
            }

            actions
        }
        .background(AppColors.background)
        .interactiveDismissDisabled(isDirty)
        .alert("projects.form.discard.title", isPresented: $showsDiscardAlert) {
            Button("projects.form.discard.keepEditing", role: .cancel) {}
            Button("projects.form.discard.action", role: .destructive) {
                discard()
            }
        }
    }

    private var isDirty: Bool {
        !projectName.isEmpty || !description.isEmpty
    }

    private var canSave: Bool {
        ProjectValidation.isValidName(projectName)
    }

    private var header: some View {
        ZStack {
            Text("projects.form.title")
                .appTypography(AppTypography.headingLarge)
                .foregroundStyle(AppColors.primaryText)

            HStack {
                Button(action: cancel) {
                    Image(systemName: "chevron.left")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(AppColors.primaryText)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .background(.quaternary.opacity(0.45), in: Circle())
                .accessibilityLabel(String(localized: "common.back"))
                .accessibilityIdentifier("projects.newProject.back")

                Spacer()
            }
        }
        .padding(.horizontal, AppSpacing.extraLarge)
        .padding(.top, AppSpacing.small)
        .padding(.bottom, AppSpacing.medium)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("projects.form.name.label")
                .appTypography(AppTypography.headingSmall)
                .foregroundStyle(AppColors.secondaryText)

            TextField("projects.form.name.placeholder", text: $projectName)
                .textFieldStyle(.plain)
                .appTypography(AppTypography.bodyLarge)
                .foregroundStyle(AppColors.primaryText)
                .focused($focusedField, equals: .name)
                .textInputAutocapitalization(.words)
                .submitLabel(.next)
                .onSubmit {
                    focusedField = .description
                }
                .onChange(of: projectName) { _, newValue in
                    projectName = String(newValue.prefix(ProjectValidation.nameLimit))
                    showsNameError = false
                }
                .padding(.horizontal, AppSpacing.large)
                .frame(height: 56)
                .background(AppColors.background)
                .overlay {
                    RoundedRectangle(cornerRadius: AppCornerRadius.large)
                        .stroke(
                            showsNameError ? AppColors.error : Color(uiColor: .systemGray4),
                            lineWidth: 1.5
                        )
                }
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large))
                .accessibilityIdentifier("projects.newProject.name")

            if showsNameError {
                Text("projects.form.name.error")
                    .appTypography(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.error)
            }
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("projects.form.description.label")
                .appTypography(AppTypography.headingSmall)
                .foregroundStyle(AppColors.secondaryText)

            ZStack(alignment: .topLeading) {
                if description.isEmpty {
                    Text("projects.form.description.placeholder")
                        .appTypography(AppTypography.bodyLarge)
                        .foregroundStyle(AppColors.secondaryText)
                        .padding(.horizontal, AppSpacing.large)
                        .padding(.vertical, AppSpacing.large)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $description)
                    .appTypography(AppTypography.bodyLarge)
                    .foregroundStyle(AppColors.primaryText)
                    .focused($focusedField, equals: .description)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, AppSpacing.medium)
                    .padding(.vertical, AppSpacing.small)
                    .onChange(of: description) { _, newValue in
                        description = String(newValue.prefix(ProjectValidation.descriptionLimit))
                    }
            }
            .frame(minHeight: 260)
            .background(AppColors.background)
            .overlay {
                RoundedRectangle(cornerRadius: AppCornerRadius.large)
                    .stroke(Color(uiColor: .systemGray4), lineWidth: 1.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large))
            .accessibilityIdentifier("projects.newProject.description")
        }
    }

    private var actions: some View {
        VStack(spacing: AppSpacing.large) {
            Button(action: save) {
                Text("projects.form.save")
                    .appTypography(AppTypography.labelButton)
                    .foregroundStyle(AppColors.primaryActionLabel)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        AppColors.brandBlueBottom,
                        in: RoundedRectangle(cornerRadius: AppCornerRadius.large)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.3)
            .accessibilityIdentifier("projects.newProject.save")

            Button(action: cancel) {
                Text("projects.form.cancel")
                    .appTypography(AppTypography.labelButton)
                    .foregroundStyle(AppColors.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        AppColors.background,
                        in: RoundedRectangle(cornerRadius: AppCornerRadius.large)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: AppCornerRadius.large)
                            .stroke(Color(uiColor: .systemGray4), lineWidth: 1.5)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("projects.newProject.cancel")
        }
        .padding(.horizontal, AppSpacing.extraLarge)
        .padding(.top, AppSpacing.large)
        .padding(.bottom, AppSpacing.large)
    }

    private func save() {
        let trimmedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let isValid = ProjectValidation.isValidName(trimmedName)
            && ProjectValidation.isValidDescription(description)

        showsNameError = !ProjectValidation.isValidName(trimmedName)
        guard isValid else {
            focusedField = showsNameError ? .name : .description
            return
        }

        onSave(trimmedName, description.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func cancel() {
        guard isDirty else {
            discard()
            return
        }

        showsDiscardAlert = true
    }

    private func discard() {
        onCancel()
        dismiss()
    }
}

enum ProjectValidation {
    static let nameLimit = 50
    static let descriptionLimit = 500

    static func isValidName(_ name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...nameLimit).contains(trimmedName.count) && !trimmedName.isEmpty
    }

    static func isValidDescription(_ description: String) -> Bool {
        description.count <= descriptionLimit
    }
}

#Preview {
    NewProjectView(onSave: { _, _ in }, onCancel: {})
}
