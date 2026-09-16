//
//  CreatedProjectOwnerActionController.swift
//  roomscan
//

import Foundation
import Observation

/// Owns the post-create Edit/Delete presentation state and sequencing for `HomeView`.
///
/// The glue lives here rather than inline in the view so the binding order, flight
/// invalidation, and detail-dismiss branching can be exercised directly by tests.
@MainActor
@Observable
final class CreatedProjectOwnerActionController {
    var pending: CreatedProjectOwnerAction?
    var activeEdit: ProjectSummary?
    var activeDelete: ProjectSummary?

    @ObservationIgnored private var flight = CreatedProjectOwnerActionFlight()
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Stages `action`, invalidating any in-flight handoff first.
    ///
    /// When the created-project detail is still presented, `dismissDetail` closes it and the
    /// presentation starts from its `onDismiss`; otherwise the handoff starts immediately and
    /// its task is returned so callers (and tests) can await completion.
    @discardableResult
    func begin(
        _ action: CreatedProjectOwnerAction,
        detailIsPresented: Bool,
        dismissDetail: () -> Void
    ) -> Task<Void, Never>? {
        beginFlight()
        mutate { $0.begin(action) }
        if detailIsPresented {
            dismissDetail()
            return nil
        } else {
            return presentAfterDetailDismiss()
        }
    }

    /// Presents the staged action once the created-project detail has dismissed.
    @discardableResult
    func presentAfterDetailDismiss() -> Task<Void, Never>? {
        guard CreatedProjectOwnerActionHandoff.actionAwaitingPresentation(pending) != nil else {
            return nil
        }
        let generation = beginFlight()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await CreatedProjectOwnerActionHandoff.presentAfterDetailDismiss(
                load: { self.session },
                store: { session in
                    guard self.flight.isCurrent(generation) else { return }
                    self.apply(session)
                },
                isCurrent: {
                    !Task.isCancelled && self.flight.isCurrent(generation)
                }
            )
        }
        self.task = task
        return task
    }

    /// Stops an unacknowledged handoff (e.g. the user left the Projects tab).
    func cancelUnacknowledgedPresentation() {
        beginFlight()
        mutate { $0.abandonUnacknowledgedPresentation() }
    }

    /// Clears `pending` once the edit cover has actually appeared.
    func acknowledgeEditAppeared(_ project: ProjectSummary) {
        mutate { $0.acknowledgeEditPresentation(project) }
    }

    /// Clears `pending` once the delete confirmation is dismissed (button or `isPresented`).
    func acknowledgeDeleteDismissed() {
        mutate { session in
            guard case .delete(let project) = session.pending else { return }
            session.acknowledgeDeletePresentation(project)
        }
    }

    @discardableResult
    private func beginFlight() -> Int {
        task?.cancel()
        task = nil
        return flight.begin()
    }

    private var session: CreatedProjectOwnerActionHandoffSession {
        CreatedProjectOwnerActionHandoffSession.snapshot(
            pending: pending,
            activeEdit: activeEdit,
            activeDelete: activeDelete
        )
    }

    private func apply(_ session: CreatedProjectOwnerActionHandoffSession) {
        pending = session.pending
        activeEdit = session.activeEdit
        activeDelete = session.activeDelete
    }

    private func mutate(_ body: (inout CreatedProjectOwnerActionHandoffSession) -> Void) {
        var session = session
        body(&session)
        apply(session)
    }
}
