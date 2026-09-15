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
                    CreatedProjectOwnerActionHandoffSession.mutate(
                        pending: &pendingOwnerAction,
                        activeEdit: &projectToEdit,
                        activeDelete: &projectPendingDelete
                    ) { session in
                        session.acknowledgeEditPresentation(project)
                    }
                }
            }
            .projectDeleteConfirmationAlert(
                projectPendingDelete: $projectPendingDelete,
                onConfirmDelete: { projectID in
                    Task {
                        await projectsViewModel.deleteProject(id: projectID)
                    }
                },
                onPresented: { project in
                    CreatedProjectOwnerActionHandoffSession.mutate(
                        pending: &pendingOwnerAction,
                        activeEdit: &projectToEdit,
                        activeDelete: &projectPendingDelete
                    ) { session in
                        session.acknowledgeDeletePresentation(project)
                    }
                }
            )
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
