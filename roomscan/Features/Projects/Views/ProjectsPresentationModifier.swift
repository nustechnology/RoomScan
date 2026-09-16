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

/// Identifies a presented scan flow and optionally preselects a project on review.
struct ActiveScanFlow: Identifiable, Equatable {
    let id: UUID
    let sourceProjectID: String?

    /// Creates a scan-flow presentation value.
    /// - Parameters:
    ///   - id: Stable identity for `fullScreenCover(item:)`.
    ///   - sourceProjectID: Project to preselect on the review screen, if any.
    init(id: UUID = UUID(), sourceProjectID: String?) {
        self.id = id
        self.sourceProjectID = sourceProjectID
    }
}

/// Moves a pending Add Scan request into the active scan presentation after project detail dismisses.
enum ActiveScanFlowHandoff {
    /// Returns the flow still waiting to be presented, without clearing it.
    ///
    /// Pending stays set until `acknowledgePresented` so a dropped cover can be retried.
    static func flowAwaitingPresentation(_ pending: ActiveScanFlow?) -> ActiveScanFlow? {
        pending
    }

    /// The pending flow to assign now, or `nil` when nothing is waiting or that cover is already active.
    static func flowToAssign(pending: ActiveScanFlow?, active: ActiveScanFlow?) -> ActiveScanFlow? {
        guard let pending else { return nil }
        guard active?.id != pending.id else { return nil }
        return pending
    }

    /// Clears `pending` only after the matching scan cover has actually appeared.
    static func acknowledgePresented(_ presented: ActiveScanFlow, pending: inout ActiveScanFlow?) {
        guard pending?.id == presented.id else { return }
        pending = nil
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
    let syncEngine: SyncEngine?
    var currentUserID: String

    @Binding var activeScanFlow: ActiveScanFlow?
    @Binding var pendingActiveScanFlow: ActiveScanFlow?
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
                    presentPendingScanFlowAfterDetailDismiss()
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
            .task {
                await viewModel.loadInitialProjects()
                checkDraftRecovery()
            }
            .fullScreenCover(
                item: $activeScanFlow,
                onDismiss: {
                    if let savedScan = pendingSavedScanForDetails {
                        pendingSavedScanForDetails = nil
                        savedScanForDetails = savedScan
                    }
                },
                content: { flow in
                    ScanFlowCoordinatorView(
                        sourceProjectID: flow.sourceProjectID,
                        recoveredDraft: recoveredDraft,
                        projectsService: projectsService,
                        onComplete: { savedScan in
                            recoveredDraft = nil
                            activeScanFlow = nil
                            if let savedScan {
                                pendingSavedScanForDetails = savedScan
                            }
                            Task {
                                await viewModel.refreshProjects()
                            }
                        },
                        onCancel: {
                            recoveredDraft = nil
                            activeScanFlow = nil
                        }
                    )
                    .onAppear {
                        ActiveScanFlowHandoff.acknowledgePresented(
                            flow,
                            pending: &pendingActiveScanFlow
                        )
                    }
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
                    activeScanFlow = ActiveScanFlow(sourceProjectID: draft.projectID)
                    recoveredDraftToPrompt = nil
                }
                Button(String(localized: "scan.recovery.discard"), role: .destructive) {
                    storageService.clearDraftManifest()
                    draft.deleteManagedFiles()
                    recoveredDraftToPrompt = nil
                }
            } message: { _ in
                Text(String(localized: "scan.recovery.message"))
            }
            .projectOwnerActionPresentation(
                projectToEdit: $projectToEdit,
                projectPendingDelete: $projectPendingDelete,
                projectsViewModel: viewModel
            )
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

    /// Presents a pending Add Scan after detail dismiss, retrying once if the first assignment is rejected.
    ///
    /// The pending value is cleared only when the scan cover appears, so a swallowed presentation can be retried.
    private func presentPendingScanFlowAfterDetailDismiss() {
        guard ActiveScanFlowHandoff.flowAwaitingPresentation(pendingActiveScanFlow) != nil else { return }
        Task { @MainActor in
            await PresentationHandoff.presentAfterDismiss {
                assignPendingScanFlowIfNeeded()
            }
        }
    }

    /// Assigns the still-pending flow when no matching cover is currently presented.
    private func assignPendingScanFlowIfNeeded() {
        guard let flow = ActiveScanFlowHandoff.flowToAssign(
            pending: pendingActiveScanFlow,
            active: activeScanFlow
        ) else { return }
        activeScanFlow = flow
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

    /// Project detail cover; Add Scan stashes a pending `ActiveScanFlow` then dismisses.
    private func projectDetailCover(for project: ProjectSummary) -> some View {
        ProjectDetailView(
            project: project,
            projectsService: projectsService,
            scanDetailService: scanDetailService,
            notesService: notesService,
            shareService: shareService,
            syncEngine: syncEngine,
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
                pendingActiveScanFlow = ActiveScanFlow(sourceProjectID: projectID)
                selectedProject = nil
            },
            onEdit: { project in
                projectToEdit = project
            },
            onDelete: { project in
                projectPendingDelete = project
            }
        )
    }

}
