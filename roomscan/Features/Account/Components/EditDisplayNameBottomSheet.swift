//
//  EditDisplayNameBottomSheet.swift
//  roomscan
//

import SwiftUI

struct EditDisplayNameBottomSheet: View {
    @Binding var displayName: String

    let validationMessage: String?
    let errorMessage: String?
    let isSaving: Bool
    let canSave: Bool
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text("account.editName.fieldLabel")
                        .appTypography(AppTypography.labelField)
                        .foregroundStyle(AppColors.secondaryText)

                    TextField(
                        String(localized: "account.editName.placeholder"),
                        text: $displayName
                    )
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .disabled(isSaving)
                    .padding(.horizontal, AppSpacing.medium)
                    .padding(.vertical, AppSpacing.large)
                    .background(
                        RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous)
                            .stroke(
                                validationMessage == nil ? Color.primary.opacity(0.14) : AppColors.error,
                                lineWidth: 1
                            )
                    )
                    .accessibilityIdentifier("account.editName.field")

                    if let validationMessage {
                        Text(validationMessage)
                            .appTypography(AppTypography.captionMedium)
                            .foregroundStyle(AppColors.error)
                            .accessibilityIdentifier("account.editName.validation")
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .appTypography(AppTypography.captionMedium)
                            .foregroundStyle(AppColors.error)
                            .accessibilityIdentifier("account.editName.error")
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(AppSpacing.extraLarge)
            .background(AppColors.background)
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(
                    title: isSaving
                        ? String(localized: "account.editName.saving")
                        : String(localized: "account.editName.save"),
                    systemImageName: isSaving ? nil : "checkmark",
                    color: AppColors.brandBlueBottom,
                    action: onSave,
                    foregroundColor: AppColors.primaryActionLabel,
                    cornerRadius: AppCornerRadius.medium,
                    isLoading: isSaving,
                    accessibilityIdentifier: "account.editName.save"
                )
                .disabled(!canSave)
                .opacity((canSave || isSaving) ? 1 : 0.6)
                .padding(.horizontal, AppSpacing.extraLarge)
                .padding(.top, AppSpacing.medium)
                .padding(.bottom, AppSpacing.large)
                .background(AppColors.background)
            }
            .navigationTitle(String(localized: "account.editName.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .background(AppColors.background)
        }
        .background(AppColors.background)
        .presentationBackground(AppColors.background)
        .presentationDetents([.fraction(0.45), .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSaving)
    }
}
