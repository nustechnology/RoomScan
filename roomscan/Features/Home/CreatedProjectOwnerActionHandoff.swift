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

/// Mutable presentation state for Edit/Delete after the created-project detail dismisses.
struct CreatedProjectOwnerActionHandoffSession: Equatable {
    var pending: CreatedProjectOwnerAction?
    var activeEdit: ProjectSummary?
    var activeDelete: ProjectSummary?

    /// Starts a new owner action, clearing any stuck presentation bindings first.
    mutating func begin(_ action: CreatedProjectOwnerAction) {
        activeEdit = nil
        activeDelete = nil
        pending = action
    }

    /// Assigns the pending action onto edit/delete presentation state when not already active.
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

    /// Clears pending when the delete alert binding becomes active.
    mutating func acknowledgeDeleteAssignment(_ project: ProjectSummary) {
        pending = CreatedProjectOwnerActionHandoff.pendingAfterAcknowledging(
            .delete(project),
            pending: pending
        )
    }

    /// After assign retries + an acknowledgment window, drop unconfirmed work.
    ///
    /// Edit is acknowledged only when the cover appears (`acknowledgeEditPresentation`).
    /// If pending is still set, the cover never confirmed — clear the stuck edit binding
    /// and pending so the action cannot replay on the next detail dismiss.
    ///
    /// Delete is acknowledged when the alert binding is assigned, so pending is usually
    /// already nil here; leftover pending only means assignment never stuck.
    mutating func finishUnacknowledgedPresentation() {
        guard let pending else { return }
        switch pending {
        case .edit(let project):
            if activeEdit?.id == project.id {
                activeEdit = nil
            }
        case .delete:
            break
        }
        self.pending = nil
    }
}

/// Moves a pending Edit/Delete request into presentation after the created-project detail dismisses.
enum CreatedProjectOwnerActionHandoff {
    /// How long to wait for edit-cover `onAppear` acknowledgment after assign retries.
    static let acknowledgmentPollCount = 6
    static let acknowledgmentPollNanoseconds: UInt64 = 50_000_000

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

    /// Runs assign retries, polls live session state for acknowledgment, then tears down
    /// unconfirmed edit work.
    ///
    /// `load` / `store` must read and write the same storage the UI acknowledgments mutate
    /// (HomeView bindings or a test-held session) so an `onAppear` clear of `pending` is
    /// visible to the poll loop.
    @MainActor
    static func runPresentationAttempts(
        load: @MainActor () -> CreatedProjectOwnerActionHandoffSession,
        store: @MainActor (CreatedProjectOwnerActionHandoffSession) -> Void,
        sleepNanoseconds: @MainActor (UInt64) async -> Void = {
            try? await Task.sleep(nanoseconds: $0)
        }
    ) async {
        await Task.yield()
        mutate(load: load, store: store) { $0.assignIfNeeded() }
        await Task.yield()
        mutate(load: load, store: store) { $0.assignIfNeeded() }

        for _ in 0..<acknowledgmentPollCount {
            if load().pending == nil { return }
            await sleepNanoseconds(acknowledgmentPollNanoseconds)
        }

        mutate(load: load, store: store) { $0.finishUnacknowledgedPresentation() }
    }

    @MainActor
    private static func mutate(
        load: @MainActor () -> CreatedProjectOwnerActionHandoffSession,
        store: @MainActor (CreatedProjectOwnerActionHandoffSession) -> Void,
        _ body: (inout CreatedProjectOwnerActionHandoffSession) -> Void
    ) {
        var session = load()
        body(&session)
        store(session)
    }
}
