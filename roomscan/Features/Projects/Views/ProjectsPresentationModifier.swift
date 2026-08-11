//
//  ProjectsPresentationModifier.swift
//  roomscan
//

import SwiftUI

struct ScanDetailDestination: Hashable, Identifiable {
    let projectID: String
    let projectName: String?
    let scan: RoomScanSummary

    var id: String {
        "\(projectID)-\(scan.id)"
    }
}

struct ProjectsPresentationModifier: ViewModifier {
    @Binding var selectedProject: ProjectSummary?
    @Binding var selectedScanDetail: ScanDetailDestination?
    @Binding var shareInput: ShareScreenInput?
    @Binding var projectToEdit: ProjectSummary?
    @Binding var projectPendingDelete: ProjectSummary?
    @Binding var isShowingDetail: Bool
    var viewModel: ProjectsViewModel
    let projectsService: any ProjectsService
    let scanDetailService: (any ScanDetailService)?
    let notesService: any NotesService
    let shareService: any ShareService
    var currentUserID: String

    @Binding var showsScanFlow: Bool
    @Binding var scanningSourceProjectID: String?
    @Binding var pendingScanSourceProjectID: String?
    @Binding var recoveredDraft: RoomScanDraft?
    @Binding var recoveredDraftToPrompt: RoomScanDraft?
    @Binding var savedScanForDetails: RoomScanSummary?
    @Binding var pendingSavedScanForDetails: RoomScanSummary?
    var storageService: ScanStorageService

    // swiftlint:disable:next function_body_length
    func body(content: Content) -> some View {
        content
            .fullScreenCover(
                item: $selectedProject,
                onDismiss: {
                    if let projectID = pendingScanSourceProjectID {
                        pendingScanSourceProjectID = nil
                        scanningSourceProjectID = projectID
                        showsScanFlow = true
                    }
                },
                content: { project in
                    projectDetailCover(for: project)
                }
            )
            .fullScreenCover(item: $shareInput) { input in
                ShareView(input: input, service: shareService)
            }
            .fullScreenCover(item: $selectedScanDetail) { destination in
                NavigationStack {
                    scanDetailView(for: destination)
                }
            }
            .onChange(of: selectedScanDetail) { _, destination in
                isShowingDetail = destination != nil
            }
            .task {
                await viewModel.loadInitialProjects()
                checkDraftRecovery()
            }
            .fullScreenCover(
                isPresented: $showsScanFlow,
                onDismiss: {
                    if let savedScan = pendingSavedScanForDetails {
                        pendingSavedScanForDetails = nil
                        savedScanForDetails = savedScan
                    }
                },
                content: {
                    ScanFlowCoordinatorView(
                        sourceProjectID: scanningSourceProjectID,
                        recoveredDraft: recoveredDraft,
                        projectsService: projectsService,
                        onComplete: { savedScan in
                            recoveredDraft = nil
                            showsScanFlow = false
                            if let savedScan {
                                pendingSavedScanForDetails = savedScan
                            }
                            Task {
                                await viewModel.refreshProjects()
                            }
                        },
                        onCancel: {
                            recoveredDraft = nil
                            showsScanFlow = false
                        }
                    )
                }
            )
            .fullScreenCover(item: $savedScanForDetails) { savedScan in
                ScanCompletionView(
                    scan: savedScan,
                    onDone: {
                        savedScanForDetails = nil
                    }
                )
            }
            .alert(
                String(localized: "scan.recovery.title"),
                isPresented: Binding(
                    get: { recoveredDraftToPrompt != nil },
                    set: { if !$0 { recoveredDraftToPrompt = nil } }
                ),
                presenting: recoveredDraftToPrompt
            ) { draft in
                Button(String(localized: "scan.recovery.resume")) {
                    recoveredDraft = draft
                    scanningSourceProjectID = draft.projectID
                    showsScanFlow = true
                    recoveredDraftToPrompt = nil
                }
                Button(String(localized: "scan.recovery.discard"), role: .destructive) {
                    storageService.clearDraftManifest()
                    try? FileManager.default.removeItem(at: draft.meshFileURL)
                    try? FileManager.default.removeItem(at: draft.thumbnailFileURL)
                    recoveredDraftToPrompt = nil
                }
            } message: { _ in
                Text(String(localized: "scan.recovery.message"))
            }
            .fullScreenCover(item: $projectToEdit) { project in
                editProjectCover(for: project)
            }
            .alert(
                String(localized: "projects.delete.title"),
                isPresented: Binding(
                    get: { projectPendingDelete != nil },
                    set: { if !$0 { projectPendingDelete = nil } }
                ),
                presenting: projectPendingDelete
            ) { project in
                Button(String(localized: "projects.delete.cancel"), role: .cancel) {
                    projectPendingDelete = nil
                }
                Button(String(localized: "projects.delete.confirm"), role: .destructive) {
                    let projectID = project.id
                    projectPendingDelete = nil
                    Task {
                        await viewModel.deleteProject(id: projectID)
                    }
                }
            } message: { project in
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "projects.delete.message.format"),
                        max(project.scanCount, project.roomScans.count),
                        project.name
                    )
                )
            }
            .onChange(of: viewModel.showsDeleteSuccessToast) { _, showsToast in
                guard showsToast else { return }
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    viewModel.dismissDeleteSuccessToast()
                }
            }
            .onChange(of: viewModel.showsActionErrorToast) { _, showsToast in
                guard showsToast, projectToEdit == nil else { return }
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    viewModel.dismissActionErrorToast()
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func checkDraftRecovery() {
        if let draft = storageService.loadDraftManifest() {
            recoveredDraftToPrompt = draft
        }
    }

    private func scanDetailView(for destination: ScanDetailDestination) -> some View {
        ScanDetailView(
            viewModel: ScanDetailViewModel(
                projectID: destination.projectID,
                scan: destination.scan,
                currentUserID: currentUserID,
                service: projectsService,
                scanDetailService: scanDetailService
            ),
            projectID: destination.projectID,
            projectName: destination.projectName,
            notesService: notesService,
            shareService: shareService,
            onScanUpdated: { updatedScan in
                viewModel.applyUpdatedScan(
                    projectID: destination.projectID,
                    scan: updatedScan
                )
            },
            onScanDeleted: {
                viewModel.applyDeletedScan(
                    projectID: destination.projectID,
                    scanID: destination.scan.id
                )
            },
            onShare: {}
        )
    }

    private func projectDetailCover(for project: ProjectSummary) -> some View {
        ProjectDetailView(
            project: project,
            projectsService: projectsService,
            scanDetailService: scanDetailService,
            notesService: notesService,
            shareService: shareService,
            currentUserID: currentUserID,
            onScanUpdated: { updatedScan in
                viewModel.applyUpdatedScan(
                    projectID: project.id,
                    scan: updatedScan
                )
            },
            onScanDeleted: { scanID in
                viewModel.applyDeletedScan(
                    projectID: project.id,
                    scanID: scanID
                )
            },
            onAddScan: { projectID in
                pendingScanSourceProjectID = projectID
                selectedProject = nil
            }
        )
    }

    private func editProjectCover(for project: ProjectSummary) -> some View {
        NewProjectView(
            mode: .edit,
            initialName: project.name,
            initialDescription: project.description,
            onSave: { form in
                let didUpdate = await viewModel.updateProject(
                    id: project.id,
                    name: form.name,
                    description: form.projectDescription
                )
                if didUpdate {
                    projectToEdit = nil
                }
                return didUpdate
            },
            onCancel: {
                projectToEdit = nil
                viewModel.dismissActionErrorToast()
            }
        )
        .alert(
            String(localized: "projects.action.error"),
            isPresented: Binding(
                get: { viewModel.showsActionErrorToast },
                set: { if !$0 { viewModel.dismissActionErrorToast() } }
            )
        ) {
            Button(String(localized: "projects.action.error.dismiss"), role: .cancel) {
                viewModel.dismissActionErrorToast()
            }
        }
    }
}
