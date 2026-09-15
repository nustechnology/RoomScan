//
//  CreatedProjectOwnerActionPresentation.swift
//  roomscan
//

import SwiftUI

/// Edit cover and delete confirmation for owner actions after the post-create detail dismisses.
struct CreatedProjectOwnerActionPresentation: ViewModifier {
    @Binding var projectToEdit: ProjectSummary?
    @Binding var projectPendingDelete: ProjectSummary?
    @Binding var pendingOwnerAction: CreatedProjectOwnerAction?
    var projectsViewModel: ProjectsViewModel

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $projectToEdit) { project in
                ProjectEditCoverView(
                    project: project,
                    viewModel: projectsViewModel,
                    onDismiss: { projectToEdit = nil }
                )
                .onAppear {
                    pendingOwnerAction =
                        CreatedProjectOwnerActionHandoff.pendingAfterAcknowledging(
                            .edit(project),
                            pending: pendingOwnerAction
                        )
                }
            }
            .projectDeleteConfirmationAlert(projectPendingDelete: $projectPendingDelete) { projectID in
                Task {
                    await projectsViewModel.deleteProject(id: projectID)
                }
            }
            .onChange(of: projectPendingDelete) { _, project in
                guard let project else { return }
                pendingOwnerAction =
                    CreatedProjectOwnerActionHandoff.pendingAfterAcknowledging(
                        .delete(project),
                        pending: pendingOwnerAction
                    )
            }
    }
}

extension View {
    func createdProjectOwnerActionPresentation(
        projectToEdit: Binding<ProjectSummary?>,
        projectPendingDelete: Binding<ProjectSummary?>,
        pendingOwnerAction: Binding<CreatedProjectOwnerAction?>,
        projectsViewModel: ProjectsViewModel
    ) -> some View {
        modifier(
            CreatedProjectOwnerActionPresentation(
                projectToEdit: projectToEdit,
                projectPendingDelete: projectPendingDelete,
                pendingOwnerAction: pendingOwnerAction,
                projectsViewModel: projectsViewModel
            )
        )
    }
}
