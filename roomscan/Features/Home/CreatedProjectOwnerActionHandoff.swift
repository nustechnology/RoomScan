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

    /// Clears the active edit/delete binding for the pending action so a later
    /// `assignIfNeeded` can retrigger `fullScreenCover(item:)` / alert presentation.
    mutating func clearActivePresentationMatchingPending() {
        guard let pending else { return }
        switch pending {
        case .edit(let project):
            if activeEdit?.id == project.id {
                activeEdit = nil
            }
        case .delete(let project):
            if activeDelete?.id == project.id {
                activeDelete = nil
            }
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

    /// After the retry window, drop pending so the action cannot replay on the next dismiss.
    ///
    /// Keeps an assigned `activeEdit` binding: tearing it down here would discard a cover
    /// that is still appearing after a slow detail-dismiss transition. Stuck bindings are
    /// cleared on the next `begin(_:)`.
    mutating func finishUnacknowledgedPresentation() {
        pending = nil
    }
}

/// Moves a pending Edit/Delete request into presentation after the created-project detail dismisses.
enum CreatedProjectOwnerActionHandoff {
    /// Retries (nil-then-set) while waiting for edit-cover `onAppear` acknowledgment.
    /// ~2s window so slower detail-dismiss transitions still have time to present.
    static let acknowledgmentPollCount = 20
    static let acknowledgmentPollNanoseconds: UInt64 = 100_000_000

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

    /// Defers one turn, then repeatedly force-retriggers presentation until acknowledged.
    ///
    /// Each poll clears the matching active binding and reassigns on a separate store so
    /// SwiftUI can present after the created-detail cover finishes dismissing. `load` /
    /// `store` must share storage with UI acknowledgments so an `onAppear` clear of
    /// `pending` stops the loop. After the ~2s window, pending is cleared to prevent
    /// replay while an assigned edit binding is kept for a late-appearing cover.
    @MainActor
    static func runPresentationAttempts(
        load: @MainActor () -> CreatedProjectOwnerActionHandoffSession,
        store: @MainActor (CreatedProjectOwnerActionHandoffSession) -> Void,
        sleepNanoseconds: @MainActor (UInt64) async -> Void = {
            try? await Task.sleep(nanoseconds: $0)
        }
    ) async {
        // Let the created-project detail cover begin dismissing first.
        await Task.yield()

        for _ in 0..<acknowledgmentPollCount {
            if load().pending == nil { return }

            // Force nil-then-set across separate stores so item-based covers retrigger.
            mutate(load: load, store: store) { $0.clearActivePresentationMatchingPending() }
            await Task.yield()
            mutate(load: load, store: store) { $0.assignIfNeeded() }

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
