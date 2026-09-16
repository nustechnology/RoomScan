//
//  ProjectOwnerActionPresentation.swift
//  roomscan
//

import SwiftUI

/// Shared Edit cover + Delete confirmation surfaces for project owner actions.
///
/// Both the Projects list and the post-create handoff present the same two pieces over their
/// own bindings; callers that need to acknowledge a handoff pass `onEditAppeared` /
/// `onDeleteDismissed`, and the list flow leaves them nil.
struct ProjectOwnerActionPresentation: ViewModifier {
    @Binding var projectToEdit: ProjectSummary?
    @Binding var projectPendingDelete: ProjectSummary?
    var projectsViewModel: ProjectsViewModel
    var onEditAppeared: ((ProjectSummary) -> Void)?
    var onDeleteDismissed: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $projectToEdit) { project in
                ProjectEditCoverView(
                    project: project,
                    viewModel: projectsViewModel,
                    onDismiss: { projectToEdit = nil }
                )
                .onAppear {
                    onEditAppeared?(project)
                }
            }
            .projectDeleteConfirmationAlert(
                projectPendingDelete: $projectPendingDelete,
                onConfirmDelete: { projectID in
                    Task {
                        await projectsViewModel.deleteProject(id: projectID)
                    }
                },
                onUserDismissed: onDeleteDismissed
            )
    }
}

extension View {
    func projectOwnerActionPresentation(
        projectToEdit: Binding<ProjectSummary?>,
        projectPendingDelete: Binding<ProjectSummary?>,
        projectsViewModel: ProjectsViewModel,
        onEditAppeared: ((ProjectSummary) -> Void)? = nil,
        onDeleteDismissed: (() -> Void)? = nil
    ) -> some View {
        modifier(
            ProjectOwnerActionPresentation(
                projectToEdit: projectToEdit,
                projectPendingDelete: projectPendingDelete,
                projectsViewModel: projectsViewModel,
                onEditAppeared: onEditAppeared,
                onDeleteDismissed: onDeleteDismissed
            )
        )
    }
}
