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

    /// Clears pending for a delete handoff once presentation has been settled by the
    /// handoff loop (one clear+reassign after dismiss grace). Alert message `onAppear`
    /// is not used — system alerts flatten message views and may not run lifecycle hooks.
    mutating func acknowledgeDeletePresentation(_ project: ProjectSummary) {
        pending = CreatedProjectOwnerActionHandoff.pendingAfterAcknowledging(
            .delete(project),
            pending: pending
        )
    }

    /// After the retry window, drop the unacknowledged handoff entirely.
    ///
    /// Clears pending and any assigned edit/delete bindings so a timed-out presentation
    /// cannot later surface over another tab. Acknowledged covers already cleared `pending`
    /// via onAppear and are unaffected by this path.
    mutating func finishUnacknowledgedPresentation() {
        pending = nil
        activeEdit = nil
        activeDelete = nil
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
    /// Total poll budget (~2s) while waiting for edit-cover / delete-alert presentation acknowledgment.
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
    /// Edit waits for cover `onAppear` acknowledgment. Delete cannot rely on alert-message
    /// lifecycle hooks, so after one clear+reassign the next grace expiry acknowledges
    /// delete while leaving `activeDelete` set (alert stays up).
    ///
    /// `load` / `store` must share storage with UI acknowledgments. After the ~2s window,
    /// unacknowledged pending and presentation bindings are cleared.
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
        var hasRetriggered = false
        var waitCyclesSinceAssign = 0

        for _ in 0..<acknowledgmentPollCount {
            guard isCurrent() else { return }
            if load().pending == nil { return }

            let shouldRetrigger =
                hasAssigned && waitCyclesSinceAssign >= retriggerGracePollCount

            if shouldRetrigger {
                if acknowledgeSettledDeleteIfReady(
                    hasRetriggered: hasRetriggered,
                    load: load,
                    store: store,
                    isCurrent: isCurrent
                ) {
                    return
                }
                mutate(load: load, store: store, isCurrent: isCurrent) {
                    $0.clearActivePresentationMatchingPending()
                }
                // Real delay so fullScreenCover(item:) / alert can observe nil before reassign.
                await sleepNanoseconds(acknowledgmentPollNanoseconds)
                guard isCurrent() else { return }
                waitCyclesSinceAssign = 0
                hasRetriggered = true
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

        await finishIfStillUnacknowledged(
            load: load,
            store: store,
            isCurrent: isCurrent
        )
    }

    /// After one delete clear+reassign, treat a still-bound confirmation as presented.
    @MainActor
    private static func acknowledgeSettledDeleteIfReady(
        hasRetriggered: Bool,
        load: @MainActor () -> CreatedProjectOwnerActionHandoffSession,
        store: @MainActor (CreatedProjectOwnerActionHandoffSession) -> Void,
        isCurrent: @MainActor () -> Bool
    ) -> Bool {
        guard hasRetriggered else { return false }
        let session = load()
        guard case .delete(let project) = session.pending else { return false }
        guard session.activeDelete?.id == project.id else { return false }
        mutate(load: load, store: store, isCurrent: isCurrent) {
            $0.acknowledgeDeletePresentation(project)
        }
        return true
    }

    /// Completes only when pending survived the full window (ack may land on the last sleep).
    @MainActor
    private static func finishIfStillUnacknowledged(
        load: @MainActor () -> CreatedProjectOwnerActionHandoffSession,
        store: @MainActor (CreatedProjectOwnerActionHandoffSession) -> Void,
        isCurrent: @MainActor () -> Bool
    ) async {
        guard isCurrent() else { return }
        guard load().pending != nil else { return }
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
