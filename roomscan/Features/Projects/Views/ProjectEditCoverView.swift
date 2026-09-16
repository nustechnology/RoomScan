//
//  ProjectEditCoverView.swift
//  roomscan
//

import SwiftUI

/// Shared edit-project full-screen cover for list and post-create flows.
struct ProjectEditCoverView: View {
    let project: ProjectSummary
    var viewModel: ProjectsViewModel
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            NewProjectView(
                mode: .edit,
                initialName: project.name,
                initialDescription: project.description,
                onSave: { form in
                    let didUpdate = await viewModel.updateProject(
                        id: project.id,
                        name: form.name,
                        description: form.projectDescription,
                        revision: project.revision
                    )
                    if didUpdate {
                        onDismiss()
                    }
                    return didUpdate
                },
                onCancel: {
                    onDismiss()
                    viewModel.dismissActionErrorToast()
                }
            )
        }
        .projectActionErrorAlert(viewModel: viewModel)
    }
}
