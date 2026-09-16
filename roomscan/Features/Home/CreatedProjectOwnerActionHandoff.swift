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
struct CreatedProjectOwnerActionFlight: Equatable {
    private(set) var generation = 0

    /// Cancels conceptual ownership of any prior flight and returns the new generation.
    mutating func begin() -> Int {
        generation &+= 1
        return generation
    }

    /// Whether `flightGeneration` is still the active handoff.
    func isCurrent(_ flightGeneration: Int) -> Bool {
        flightGeneration == generation
    }
}

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

    /// Writes this session back into the three live presentation bindings.
    func apply(
        pending: inout CreatedProjectOwnerAction?,
        activeEdit: inout ProjectSummary?,
        activeDelete: inout ProjectSummary?
    ) {
        pending = self.pending
        activeEdit = self.activeEdit
        activeDelete = self.activeDelete
    }

    /// Mutates the three bindings through a single session mapping.
    static func mutate(
        pending: inout CreatedProjectOwnerAction?,
        activeEdit: inout ProjectSummary?,
        activeDelete: inout ProjectSummary?,
        _ body: (inout CreatedProjectOwnerActionHandoffSession) -> Void
    ) {
        var session = snapshot(
            pending: pending,
            activeEdit: activeEdit,
            activeDelete: activeDelete
        )
        body(&session)
        session.apply(
            pending: &pending,
            activeEdit: &activeEdit,
            activeDelete: &activeDelete
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
    /// Edit keeps `pending` until cover `onAppear` acknowledges. Delete clears `pending` here
    /// because `activeDelete` is itself the alert presentation binding — there is nothing
    /// further to confirm, and tearing it down to "retrigger" would dismiss the alert.
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
            pending = CreatedProjectOwnerActionHandoff.pendingAfterAcknowledging(
                .delete(project),
                pending: pending
            )
        }
    }

    /// Clears pending after the edit cover actually appears.
    mutating func acknowledgeEditPresentation(_ project: ProjectSummary) {
        pending = CreatedProjectOwnerActionHandoff.pendingAfterAcknowledging(
            .edit(project),
            pending: pending
        )
    }

    /// Drops an in-flight handoff that has not been acknowledged yet (e.g. user left Projects).
    ///
    /// No-op when `pending` is already nil so an on-screen edit cover is left alone.
    mutating func abandonUnacknowledgedPresentation() {
        guard pending != nil else { return }
        pending = nil
        activeEdit = nil
        activeDelete = nil
    }
}

/// Moves a pending Edit/Delete request into presentation after the created-project detail dismisses.
///
/// Mirrors `ActiveScanFlowHandoff`: yield, assign, yield, assign again. Pending stays set for
/// edit until cover `onAppear` so a swallowed assignment can be retried on the second pass.
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

    /// Defers one turn, assigns once, yields again, then assigns a second time if still pending.
    ///
    /// Same sequencing as `presentPendingScanFlowAfterDetailDismiss`: presenting from within
    /// another cover's `onDismiss` is dropped in the same main-actor turn. The second assign
    /// retries only when SwiftUI rejected the first assignment (edit still pending; delete
    /// already cleared pending at assign).
    ///
    /// `isCurrent` must become false when a newer handoff supersedes this run.
    @MainActor
    static func presentAfterDetailDismiss(
        load: @MainActor () -> CreatedProjectOwnerActionHandoffSession,
        store: @MainActor (CreatedProjectOwnerActionHandoffSession) -> Void,
        isCurrent: @MainActor () -> Bool = { true },
        yield: @MainActor () async -> Void = { await Task.yield() }
    ) async {
        await yield()
        guard isCurrent() else { return }
        mutate(load: load, store: store, isCurrent: isCurrent) { $0.assignIfNeeded() }

        await yield()
        guard isCurrent() else { return }
        mutate(load: load, store: store, isCurrent: isCurrent) { $0.assignIfNeeded() }
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
