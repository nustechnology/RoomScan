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

/// Single-flight token for post-create Edit/Delete presentation handoffs.
typealias CreatedProjectOwnerActionFlight = PresentationFlight

/// Mutable presentation state for Edit/Delete after the created-project detail dismisses.
struct CreatedProjectOwnerActionHandoffSession: Equatable {
    var pending: CreatedProjectOwnerAction?
    var activeEdit: ProjectSummary?
    var activeDelete: ProjectSummary?

    /// Builds a session snapshot from the three live presentation bindings.
    static func snapshot(
        pending: CreatedProjectOwnerAction?,
        activeEdit: ProjectSummary?,
        activeDelete: ProjectSummary?
    ) -> CreatedProjectOwnerActionHandoffSession {
        CreatedProjectOwnerActionHandoffSession(
            pending: pending,
            activeEdit: activeEdit,
            activeDelete: activeDelete
        )
    }

    /// Starts a new owner action, clearing any stuck presentation bindings first.
    mutating func begin(_ action: CreatedProjectOwnerAction) {
        activeEdit = nil
        activeDelete = nil
        pending = action
    }

    /// Assigns the pending action onto edit/delete presentation state when not already active.
    ///
    /// Both paths keep `pending` set so `presentAfterDetailDismiss`'s second assign can retry
    /// if SwiftUI rejected the first presentation (cleared `activeEdit` / `activeDelete`).
    /// Edit acknowledges via cover `onAppear`; delete via alert dismissal (`onUserDismissed`,
    /// including the `isPresented`→false teardown). A retried-and-still-missing edit is dropped
    /// by `dropUnpresentedEditRequest` so it cannot re-present on a later detail dismiss.
    mutating func assignIfNeeded() {
        guard let action = CreatedProjectOwnerActionHandoff.actionToAssign(
            pending: pending,
            activeEdit: activeEdit,
            activeDelete: activeDelete
        ) else { return }
        switch action {
        case .edit(let project):
            activeEdit = project
        case .delete(let project):
            activeDelete = project
        }
    }

    /// Clears pending after the edit cover actually appears.
    mutating func acknowledgeEditPresentation(_ project: ProjectSummary) {
        pending = CreatedProjectOwnerActionHandoff.pendingAfterAcknowledging(
            .edit(project),
            pending: pending
        )
    }

    /// Clears pending after the delete confirmation is dismissed.
    ///
    /// Called from alert Cancel/Confirm and from `isPresented`→false teardowns that skip
    /// those buttons. Pending must not survive a dismissed alert: a later created-detail
    /// dismiss would otherwise re-present delete for an abandoned project.
    mutating func acknowledgeDeletePresentation(_ project: ProjectSummary) {
        pending = CreatedProjectOwnerActionHandoff.pendingAfterAcknowledging(
            .delete(project),
            pending: pending
        )
    }

    /// Drops a pending edit that never appeared once both presentation passes have run.
    ///
    /// The edit cover acknowledges via `onAppear`, so a surviving `.edit` means it never
    /// appeared (either every assignment was swallowed or there was no cover to appear).
    /// Clearing prevents a later created-detail dismiss from re-presenting an edit for a
    /// project the user has moved on from. No-op while a cover is active or awaiting `onAppear`.
    mutating func dropUnpresentedEditRequest() {
        guard activeEdit == nil else { return }
        guard case .edit = pending else { return }
        pending = nil
    }

    /// Drops an in-flight handoff that has not been acknowledged yet (e.g. user left Projects).
    ///
    /// No-op when `pending` is already nil so an on-screen edit cover (acked via onAppear) is
    /// left alone. Delete keeps `pending` until the user answers the alert, so this also
    /// dismisses an assigned-but-unanswered confirmation when leaving the tab.
    mutating func abandonUnacknowledgedPresentation() {
        guard pending != nil else { return }
        pending = nil
        activeEdit = nil
        activeDelete = nil
    }
}

/// Moves a pending Edit/Delete request into presentation after the created-project detail dismisses.
///
/// Uses shared `PresentationHandoff` sequencing (yield, assign, yield, assign). Pending stays set
/// until acknowledgment (edit `onAppear`, delete user dismiss) so a swallowed assignment can retry.
/// A final settle turn drops an edit that still never appeared, so it cannot re-present later.
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

    /// Runs shared post-dismiss sequencing against the owner-action session bindings.
    ///
    /// A final turn lets SwiftUI clear a rejected second assignment before deciding the edit
    /// never appeared. An accepted cover keeps `activeEdit` set and is acknowledged via
    /// `onAppear`, so only the swallowed case is dropped and must not be retried later.
    @MainActor
    static func presentAfterDetailDismiss(
        load: @MainActor () -> CreatedProjectOwnerActionHandoffSession,
        store: @MainActor (CreatedProjectOwnerActionHandoffSession) -> Void,
        isCurrent: @MainActor () -> Bool = { true },
        yield: @MainActor () async -> Void = { await Task.yield() }
    ) async {
        await PresentationHandoff.presentAfterDismiss(
            isCurrent: isCurrent,
            yield: yield
        ) {
            mutate(load: load, store: store, isCurrent: isCurrent) { $0.assignIfNeeded() }
        }
        await yield()
        guard isCurrent() else { return }
        mutate(load: load, store: store, isCurrent: isCurrent) {
            $0.dropUnpresentedEditRequest()
        }
    }

    @MainActor
    private static func mutate(
        load: @MainActor () -> CreatedProjectOwnerActionHandoffSession,
        store: @MainActor (CreatedProjectOwnerActionHandoffSession) -> Void,
        isCurrent: @MainActor () -> Bool,
        _ body: (inout CreatedProjectOwnerActionHandoffSession) -> Void
    ) {
        guard isCurrent() else { return }
        var session = load()
        body(&session)
        guard isCurrent() else { return }
        store(session)
    }
}
