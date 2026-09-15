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
                editCover(for: project)
                    .onAppear {
                        pendingOwnerAction =
                            CreatedProjectOwnerActionHandoff.pendingAfterAcknowledging(
                                .edit(project),
                                pending: pendingOwnerAction
                            )
                    }
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
                        await projectsViewModel.deleteProject(id: projectID)
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
            .onChange(of: projectPendingDelete) { _, project in
                guard let project else { return }
                pendingOwnerAction =
                    CreatedProjectOwnerActionHandoff.pendingAfterAcknowledging(
                        .delete(project),
                        pending: pendingOwnerAction
                    )
            }
    }

    private func editCover(for project: ProjectSummary) -> some View {
        NewProjectView(
            mode: .edit,
            initialName: project.name,
            initialDescription: project.description,
            onSave: { form in
                let didUpdate = await projectsViewModel.updateProject(
                    id: project.id,
                    name: form.name,
                    description: form.projectDescription,
                    revision: project.revision
                )
                if didUpdate {
                    projectToEdit = nil
                }
                return didUpdate
            },
            onCancel: {
                projectToEdit = nil
                projectsViewModel.dismissActionErrorToast()
            }
        )
        .alert(
            String(localized: "projects.action.error"),
            isPresented: Binding(
                get: { projectsViewModel.showsActionErrorToast },
                set: { if !$0 { projectsViewModel.dismissActionErrorToast() } }
            )
        ) {
            Button(String(localized: "projects.action.error.dismiss"), role: .cancel) {
                projectsViewModel.dismissActionErrorToast()
            }
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
