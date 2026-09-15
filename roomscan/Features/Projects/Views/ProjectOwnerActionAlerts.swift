//
//  ProjectOwnerActionAlerts.swift
//  roomscan
//

import SwiftUI

enum ProjectOwnerActionAlerts {
    static func deleteMessage(for project: ProjectSummary) -> Text {
        Text(
            String.localizedStringWithFormat(
                String(localized: "projects.delete.message.format"),
                max(project.scanCount, project.roomScans.count),
                project.name
            )
        )
    }
}

private struct ProjectDeleteConfirmationAlertModifier: ViewModifier {
    @Binding var projectPendingDelete: ProjectSummary?
    let onConfirmDelete: (ProjectSummary.ID) -> Void

    func body(content: Content) -> some View {
        content.alert(
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
                onConfirmDelete(projectID)
            }
        } message: { project in
            ProjectOwnerActionAlerts.deleteMessage(for: project)
        }
    }
}

private struct ProjectActionErrorAlertModifier: ViewModifier {
    var viewModel: ProjectsViewModel

    func body(content: Content) -> some View {
        content.alert(
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

extension View {
    func projectDeleteConfirmationAlert(
        projectPendingDelete: Binding<ProjectSummary?>,
        onConfirmDelete: @escaping (ProjectSummary.ID) -> Void
    ) -> some View {
        modifier(
            ProjectDeleteConfirmationAlertModifier(
                projectPendingDelete: projectPendingDelete,
                onConfirmDelete: onConfirmDelete
            )
        )
    }

    func projectActionErrorAlert(viewModel: ProjectsViewModel) -> some View {
        modifier(ProjectActionErrorAlertModifier(viewModel: viewModel))
    }
}
