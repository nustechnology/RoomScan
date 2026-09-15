//
//  CreatedProjectOwnerActionHandoffTests.swift
//  roomscanTests
//

@testable import roomscan
import XCTest

final class CreatedProjectOwnerActionHandoffTests: XCTestCase {
    private let project = ProjectSummary.testFixture()
    private let otherProject = ProjectSummary.testFixture(id: "project-2", name: "Studio")

    func testActionToAssign_presentsPendingEditWhenEditCoverIsNotActive() {
        let action = CreatedProjectOwnerActionHandoff.actionToAssign(
            pending: .edit(project),
            activeEdit: nil,
            activeDelete: nil
        )

        XCTAssertEqual(action, .edit(project))
    }

    func testActionToAssign_skipsWhenMatchingEditCoverIsAlreadyActive() {
        let action = CreatedProjectOwnerActionHandoff.actionToAssign(
            pending: .edit(project),
            activeEdit: project,
            activeDelete: nil
        )

        XCTAssertNil(action)
    }

    func testPendingAfterAcknowledging_clearsMatchingAction() {
        let remaining = CreatedProjectOwnerActionHandoff.pendingAfterAcknowledging(
            .edit(project),
            pending: .edit(project)
        )

        XCTAssertNil(remaining)
    }

    func testSession_beginClearsStuckPresentationBindings() {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: nil,
            activeEdit: otherProject,
            activeDelete: otherProject
        )

        session.begin(.edit(project))

        XCTAssertEqual(session.pending, .edit(project))
        XCTAssertNil(session.activeEdit)
        XCTAssertNil(session.activeDelete)
    }

    func testSession_clearThenAssign_retriggersEditBinding() {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .edit(project),
            activeEdit: nil,
            activeDelete: nil
        )

        session.assignIfNeeded()
        XCTAssertEqual(session.activeEdit, project)

        session.clearActivePresentationMatchingPending()
        XCTAssertNil(session.activeEdit)

        session.assignIfNeeded()
        XCTAssertEqual(session.activeEdit, project)
        XCTAssertEqual(session.pending, .edit(project))
    }

    func testSession_finishUnacknowledgedPresentation_clearsPendingAndActiveBindings() {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .edit(project),
            activeEdit: project,
            activeDelete: nil
        )

        session.finishUnacknowledgedPresentation()

        XCTAssertNil(session.pending)
        XCTAssertNil(session.activeEdit)
        XCTAssertNil(session.activeDelete)
    }

    func testFlight_beginInvalidatesPriorGeneration() {
        var flight = CreatedProjectOwnerActionFlight()
        let first = flight.begin()
        let second = flight.begin()

        XCTAssertTrue(flight.isCurrent(second))
        XCTAssertFalse(flight.isCurrent(first))
    }

    func testFlight_staleStoreGuardMatchesHomeViewPattern() {
        var flight = CreatedProjectOwnerActionFlight()
        let stale = flight.begin()
        _ = flight.begin()

        var didStore = false
        if flight.isCurrent(stale) {
            didStore = true
        }

        XCTAssertFalse(didStore)
    }

    func testSession_mutateHelperRoundTripsBindings() {
        var pending: CreatedProjectOwnerAction? = .edit(project)
        var activeEdit: ProjectSummary?
        var activeDelete: ProjectSummary?

        CreatedProjectOwnerActionHandoffSession.mutate(
            pending: &pending,
            activeEdit: &activeEdit,
            activeDelete: &activeDelete
        ) { session in
            session.assignIfNeeded()
            session.acknowledgeEditPresentation(self.project)
        }

        XCTAssertNil(pending)
        XCTAssertEqual(activeEdit, project)
        XCTAssertNil(activeDelete)
    }

    func testSession_abandonUnacknowledgedPresentation_clearsPendingAssignment() {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .edit(project),
            activeEdit: project,
            activeDelete: nil
        )

        session.abandonUnacknowledgedPresentation()

        XCTAssertNil(session.pending)
        XCTAssertNil(session.activeEdit)
        XCTAssertNil(session.activeDelete)
    }

    func testSession_abandonUnacknowledgedPresentation_leavesAcknowledgedEditAlone() {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: nil,
            activeEdit: project,
            activeDelete: nil
        )

        session.abandonUnacknowledgedPresentation()

        XCTAssertNil(session.pending)
        XCTAssertEqual(session.activeEdit, project)
    }

    func testPresentationAcknowledgment_editOnAppearClearsPending() {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .edit(project),
            activeEdit: project,
            activeDelete: nil
        )

        // Mirrors CreatedProjectOwnerActionPresentation.onAppear wiring.
        session.acknowledgeEditPresentation(project)

        XCTAssertNil(session.pending)
        XCTAssertEqual(session.activeEdit, project)
    }

    func testPresentationAcknowledgment_deleteSettleClearsPending() {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .delete(project),
            activeEdit: nil,
            activeDelete: nil
        )
        session.assignIfNeeded()

        // Mirrors handoff-loop settle ack after one clear+reassign (not alert onAppear).
        session.acknowledgeDeletePresentation(project)

        XCTAssertNil(session.pending)
        XCTAssertEqual(session.activeDelete, project)
    }
}
