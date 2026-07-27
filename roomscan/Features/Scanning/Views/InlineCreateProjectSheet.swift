//
//  InlineCreateProjectSheet.swift
//  roomscan
//

import SwiftUI

struct InlineCreateProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var projectName: String = ""
    @State private var errorMessage: String?
    @State private var isSubmitting: Bool = false

    let onCreate: (String) async -> Bool
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(String(localized: "projects.form.title"))
                    .font(.title2.bold())
                    .padding(.top, 16)

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "projects.form.name.label"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)

                    TextField(
                        String(localized: "projects.form.name.placeholder"),
                        text: $projectName
                    )
                    .textFieldStyle(.plain)
                    .onChange(of: projectName) { _, newValue in
                        if newValue.count > 50 {
                            projectName = String(newValue.prefix(50))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(errorMessage != nil ? Color.red : Color(uiColor: UIColor.systemGray4), lineWidth: 1.5)
                    )
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("inlineProjectCreate.nameField")

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .accessibilityIdentifier("inlineProjectCreate.errorText")
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    Button(role: .cancel) {
                        onCancel()
                        dismiss()
                    } label: {
                        Text(String(localized: "projects.form.cancel"))
                            .font(.body.weight(.semibold))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(uiColor: UIColor.systemGray5))
                            .cornerRadius(14)
                    }
                    .accessibilityIdentifier("inlineProjectCreate.cancelButton")

                    Button {
                        validateAndCreate()
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.blue)
                                .cornerRadius(14)
                        } else {
                            Text("Create")
                                .font(.body.weight(.semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(isInputValid ? Color.blue : Color.blue.opacity(0.4))
                                .cornerRadius(14)
                        }
                    }
                    .disabled(!isInputValid || isSubmitting)
                    .accessibilityIdentifier("inlineProjectCreate.createButton")
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
            .navigationBarTitleDisplayMode(.inline)
            .background(Color.white.ignoresSafeArea())
        }
        .presentationDetents([.height(300)])
        .foregroundStyle(Color.black)
        .preferredColorScheme(.light)
    }

    private var isInputValid: Bool {
        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 50
    }

    private func validateAndCreate() {
        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = String(localized: "projects.form.name.error")
            return
        }
        guard trimmed.count <= 50 else {
            errorMessage = String(localized: "projects.form.name.error")
            return
        }

        isSubmitting = true
        Task {
            let success = await onCreate(trimmed)
            isSubmitting = false
            if success {
                dismiss()
            } else {
                errorMessage = String(localized: "projects.form.name.error")
            }
        }
    }
}
