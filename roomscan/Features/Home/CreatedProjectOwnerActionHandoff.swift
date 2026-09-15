//
//  CreatedProjectOwnerActionHandoff.swift
//  roomscan
//

import Foundation

/// Edit or delete requested from the post-create project detail cover.
enum CreatedProjectOwnerAction: Equatable {
    case edit(ProjectSummary)
    case delete(ProjectSummary)

    var projectID: ProjectSummary.ID {
        switch self {
        case .edit(let project), .delete(let project):
            return project.id
        }
    }
}

/// Moves a pending Edit/Delete request into presentation after the created-project detail dismisses.
enum CreatedProjectOwnerActionHandoff {
    /// Returns the action still waiting to be presented, without clearing it.
    static func actionAwaitingPresentation(
        _ pending: CreatedProjectOwnerAction?
    ) -> CreatedProjectOwnerAction? {
        pending
    }

    /// The pending action to assign now, or `nil` when nothing is waiting or that UI is already active.
    static func actionToAssign(
        pending: CreatedProjectOwnerAction?,
        activeEdit: ProjectSummary?,
        activeDelete: ProjectSummary?
    ) -> CreatedProjectOwnerAction? {
        guard let pending else { return nil }
        switch pending {
        case .edit(let project):
            guard activeEdit?.id != project.id else { return nil }
            return pending
        case .delete(let project):
            guard activeDelete?.id != project.id else { return nil }
            return pending
        }
    }

    /// Returns the remaining pending value after the matching edit cover or delete alert is active.
    static func pendingAfterAcknowledging(
        _ presented: CreatedProjectOwnerAction,
        pending: CreatedProjectOwnerAction?
    ) -> CreatedProjectOwnerAction? {
        guard let pending else { return nil }
        guard pending.projectID == presented.projectID else { return pending }
        switch (pending, presented) {
        case (.edit, .edit), (.delete, .delete):
            return nil
        default:
            return pending
        }
    }
}
