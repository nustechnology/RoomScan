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

/// Single-flight token for post-create Edit/Delete presentation loops.
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
enum CreatedProjectOwnerActionHandoff {
    /// Total poll budget (~2s) while waiting for edit-cover `onAppear` acknowledgment.
    static let acknowledgmentPollCount = 20
    static let acknowledgmentPollNanoseconds: UInt64 = 100_000_000

    /// Wait this many poll intervals after an assignment before clear+reassign.
    /// Covers typical created-detail dismiss transitions (~300–400 ms).
    static let retriggerGracePollCount = 4

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

    /// Defers one turn, assigns once, then waits through a dismiss-sized grace period
    /// before any clear+reassign retrigger.
    ///
    /// `load` / `store` must share storage with UI acknowledgments. After the ~2s window,
    /// pending is cleared while an assigned edit binding is kept for a late cover.
    ///
    /// `isCurrent` must become false when a newer handoff supersedes this run.
    @MainActor
    static func runPresentationAttempts(
        load: @MainActor () -> CreatedProjectOwnerActionHandoffSession,
        store: @MainActor (CreatedProjectOwnerActionHandoffSession) -> Void,
        isCurrent: @MainActor () -> Bool = { true },
        sleepNanoseconds: @MainActor (UInt64) async -> Void = {
            try? await Task.sleep(nanoseconds: $0)
        }
    ) async {
        // Let the created-project detail cover begin dismissing first.
        await Task.yield()
        guard isCurrent() else { return }

        var hasAssigned = false
        var waitCyclesSinceAssign = 0

        for _ in 0..<acknowledgmentPollCount {
            guard isCurrent() else { return }
            if load().pending == nil { return }

            let shouldRetrigger =
                hasAssigned && waitCyclesSinceAssign >= retriggerGracePollCount

            if shouldRetrigger {
                mutate(load: load, store: store, isCurrent: isCurrent) {
                    $0.clearActivePresentationMatchingPending()
                }
                await Task.yield()
                guard isCurrent() else { return }
                waitCyclesSinceAssign = 0
            }

            if !hasAssigned || shouldRetrigger {
                mutate(load: load, store: store, isCurrent: isCurrent) { $0.assignIfNeeded() }
                hasAssigned = true
            }

            guard isCurrent() else { return }
            if load().pending == nil { return }

            await sleepNanoseconds(acknowledgmentPollNanoseconds)
            waitCyclesSinceAssign += 1
        }

        guard isCurrent() else { return }
        mutate(load: load, store: store, isCurrent: isCurrent) {
            $0.finishUnacknowledgedPresentation()
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
