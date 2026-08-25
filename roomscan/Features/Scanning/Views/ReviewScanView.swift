//
//  ReviewScanView.swift
//  roomscan
//

import SwiftUI

struct ReviewScanView: View {
    @StateObject var viewModel: ReviewScanViewModel
    let onSaveSuccess: (RoomScanSummary) -> Void
    let onScanAgain: () -> Void
    let onDiscard: () -> Void

    init(
        draft: RoomScanDraft,
        preselectedProjectID: String? = nil,
        projectsService: ProjectsService,
        onSaveSuccess: @escaping (RoomScanSummary) -> Void,
        onScanAgain: @escaping () -> Void,
        onDiscard: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: ReviewScanViewModel(
            draft: draft,
            preselectedProjectID: preselectedProjectID,
            projectsService: projectsService
        ))
        self.onSaveSuccess = onSaveSuccess
        self.onScanAgain = onScanAgain
        self.onDiscard = onDiscard
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Button {
                    viewModel.showDiscardConfirmation = true
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.primary)
                        .padding(10)
                        .background(Color(uiColor: UIColor.secondarySystemBackground))
                        .clipShape(Circle())
                }
                .accessibilityIdentifier("review.backButton")

                Spacer()

                Text(String(localized: "review.title"))
                    .font(.headline.weight(.semibold))

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 24) {
                    // 3D Model Preview Component
                    Model3DPreviewView(
                        meshURL: viewModel.draft.meshFileURL
                    )

                    // Form Inputs
                    VStack(alignment: .leading, spacing: 20) {
                        // Scan Name Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "review.label.scan_name"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)

                            TextField(String(localized: "review.placeholder.scan_name"), text: $viewModel.scanName)
                                .font(.body)
                                .onChange(of: viewModel.scanName) { _, newValue in
                                    if newValue.count > 50 {
                                        viewModel.scanName = String(newValue.prefix(50))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(
                                            viewModel.scanNameError != nil ? Color.red : Color(uiColor: UIColor.systemGray4),
                                            lineWidth: 1.5
                                        )
                                )
                                .accessibilityIdentifier("review.scanNameField")

                            if let error = viewModel.scanNameError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .accessibilityIdentifier("review.scanNameError")
                            }
                        }

                        // Select Project Dropdown Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "review.label.select_project"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(viewModel.projectSelectError == nil ? .secondary : .red)

                            Menu {
                                Button {
                                    viewModel.openCreateProjectModal()
                                } label: {
                                    Label(String(localized: "review.action.create_project"), systemImage: "plus")
                                }

                                Divider()

                                ForEach(viewModel.projects) { project in
                                    Button {
                                        viewModel.selectedProjectID = project.id
                                    } label: {
                                        HStack {
                                            Text(project.name)
                                            if viewModel.selectedProjectID == project.id {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                    .accessibilityIdentifier("review.projectOption.\(project.id)")
                                }
                            } label: {
                                HStack {
                                    Text(selectedProjectName)
                                        .font(.body)
                                        .foregroundColor(viewModel.selectedProjectID == nil ? .gray : .primary)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(
                                            viewModel.projectSelectError == nil
                                                ? Color(uiColor: UIColor.systemGray4)
                                                : Color.red,
                                            lineWidth: 1.5
                                        )
                                )
                            }
                            .accessibilityIdentifier("review.selectProjectDropdown")

                            if let error = viewModel.projectSelectError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .accessibilityIdentifier("review.selectProjectError")
                            }
                        }
                    }

                    Spacer(minLength: 20)

                    if let error = viewModel.saveErrorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("review.saveError")
                    }

                    // Primary Action: Save Scan
                    Button {
                        Task {
                            if let saved = await viewModel.saveScan() {
                                onSaveSuccess(saved)
                            }
                        }
                    } label: {
                        if viewModel.isSaving {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.blue)
                                .cornerRadius(16)
                        } else {
                            Text(String(localized: "review.action.save"))
                                .font(.body.weight(.semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(viewModel.isSaveEnabled ? Color.blue : Color.blue.opacity(0.4))
                                .cornerRadius(16)
                        }
                    }
                    .disabled(!viewModel.isSaveEnabled)
                    .accessibilityIdentifier("review.saveButton")

                    // Secondary Bottom Actions (Scan Again / Discard)
                    HStack(spacing: 16) {
                        Button {
                            viewModel.cleanupDraftCache()
                            onScanAgain()
                        } label: {
                            Text(String(localized: "review.action.scan_again"))
                                .font(.body.weight(.semibold))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.white)
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color(uiColor: UIColor.systemGray4), lineWidth: 1)
                                )
                        }
                        .accessibilityIdentifier("review.scanAgainButton")

                        Button {
                            viewModel.showDiscardConfirmation = true
                        } label: {
                            Text(String(localized: "review.action.discard"))
                                .font(.body.weight(.semibold))
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(16)
                        }
                        .accessibilityIdentifier("review.discardButton")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .foregroundStyle(Color.black)
        .preferredColorScheme(.light)
        .task {
            await viewModel.loadProjects()
        }
        .sheet(isPresented: $viewModel.showCreateProjectModal) {
            InlineCreateProjectSheet(
                onCreate: { name in
                    await viewModel.createProject(name: name)
                },
                onCancel: {
                    viewModel.cancelCreateProjectModal()
                }
            )
        }
        .alert(
            String(localized: "review.discard.title"),
            isPresented: $viewModel.showDiscardConfirmation
        ) {
            Button(String(localized: "review.discard.cancel"), role: .cancel) {}
            Button(String(localized: "review.discard.confirm"), role: .destructive) {
                viewModel.cleanupDraftCache()
                onDiscard()
            }
        } message: {
            Text(String(localized: "review.discard.message"))
        }
    }

    private var selectedProjectName: String {
        if let id = viewModel.selectedProjectID,
           let project = viewModel.projects.first(where: { $0.id == id }) {
            return project.name
        }
        return String(localized: "review.placeholder.select_project")
    }
}
