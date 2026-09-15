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

/// Binding side-effects for the shared project delete confirmation alert.
enum ProjectDeleteConfirmationActions {
    /// Clears the pending project when SwiftUI dismisses the alert.
    static func handleIsPresentedChange(
        _ isPresented: Bool,
        projectPendingDelete: inout ProjectSummary?
    ) {
        if !isPresented {
            projectPendingDelete = nil
        }
    }

    /// Dismisses the confirmation without deleting.
    static func handleCancel(
        projectPendingDelete: inout ProjectSummary?,
        onUserDismissed: (() -> Void)? = nil
    ) {
        projectPendingDelete = nil
        onUserDismissed?()
    }

    /// Clears the confirmation binding, then invokes delete for the presented project id.
    static func handleConfirm(
        project: ProjectSummary,
        projectPendingDelete: inout ProjectSummary?,
        onConfirmDelete: (ProjectSummary.ID) -> Void,
        onUserDismissed: (() -> Void)? = nil
    ) {
        let projectID = project.id
        projectPendingDelete = nil
        onUserDismissed?()
        onConfirmDelete(projectID)
    }
}

private struct ProjectDeleteConfirmationAlertModifier: ViewModifier {
    @Binding var projectPendingDelete: ProjectSummary?
    let onConfirmDelete: (ProjectSummary.ID) -> Void
    var onUserDismissed: (() -> Void)?

    func body(content: Content) -> some View {
        content.alert(
            String(localized: "projects.delete.title"),
            isPresented: Binding(
                get: { projectPendingDelete != nil },
                set: { isPresented in
                    ProjectDeleteConfirmationActions.handleIsPresentedChange(
                        isPresented,
                        projectPendingDelete: &projectPendingDelete
                    )
                }
            ),
            presenting: projectPendingDelete
        ) { project in
            Button(String(localized: "projects.delete.cancel"), role: .cancel) {
                ProjectDeleteConfirmationActions.handleCancel(
                    projectPendingDelete: &projectPendingDelete,
                    onUserDismissed: onUserDismissed
                )
            }
            Button(String(localized: "projects.delete.confirm"), role: .destructive) {
                ProjectDeleteConfirmationActions.handleConfirm(
                    project: project,
                    projectPendingDelete: &projectPendingDelete,
                    onConfirmDelete: onConfirmDelete,
                    onUserDismissed: onUserDismissed
                )
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
        onConfirmDelete: @escaping (ProjectSummary.ID) -> Void,
        onUserDismissed: (() -> Void)? = nil
    ) -> some View {
        modifier(
            ProjectDeleteConfirmationAlertModifier(
                projectPendingDelete: projectPendingDelete,
                onConfirmDelete: onConfirmDelete,
                onUserDismissed: onUserDismissed
            )
        )
    }

    func projectActionErrorAlert(viewModel: ProjectsViewModel) -> some View {
        modifier(ProjectActionErrorAlertModifier(viewModel: viewModel))
    }
}
