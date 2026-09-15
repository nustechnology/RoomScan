//
//  CreatedProjectOwnerActionHandoffTests.swift
//  roomscanTests
//

@testable import roomscan
import XCTest

final class CreatedProjectOwnerActionHandoffTests: XCTestCase {
    private let project = ProjectSummary(
        id: "project-1",
        revision: 1,
        name: "Office",
        ownerName: "Owner",
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0),
        description: "Desc",
        roomScans: [],
        scanCount: 0
    )

    private let otherProject = ProjectSummary(
        id: "project-2",
        revision: 1,
        name: "Studio",
        ownerName: "Owner",
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0),
        description: "Desc",
        roomScans: [],
        scanCount: 0
    )

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

    func testPendingAfterAcknowledging_ignoresDifferentActionKind() {
        let remaining = CreatedProjectOwnerActionHandoff.pendingAfterAcknowledging(
            .delete(project),
            pending: .edit(project)
        )

        XCTAssertEqual(remaining, .edit(project))
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

    func testSession_assignIfNeeded_setsEditBinding() {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .edit(project),
            activeEdit: nil,
            activeDelete: nil
        )

        session.assignIfNeeded()

        XCTAssertEqual(session.activeEdit, project)
        XCTAssertEqual(session.pending, .edit(project))
    }

    func testSession_assignIfNeeded_setsDeleteBinding() {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .delete(project),
            activeEdit: nil,
            activeDelete: nil
        )

        session.assignIfNeeded()

        XCTAssertEqual(session.activeDelete, project)
        XCTAssertEqual(session.pending, .delete(project))
    }

    func testSession_finishUnacknowledgedPresentation_clearsStuckEditBindingAndPending() {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .edit(project),
            activeEdit: project,
            activeDelete: nil
        )

        session.finishUnacknowledgedPresentation()

        XCTAssertNil(session.pending)
        XCTAssertNil(session.activeEdit)
    }

    func testSession_finishUnacknowledgedPresentation_noopWhenEditWasAcknowledged() {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .edit(project),
            activeEdit: project,
            activeDelete: nil
        )

        session.acknowledgeEditPresentation(project)
        session.finishUnacknowledgedPresentation()

        XCTAssertNil(session.pending)
        XCTAssertEqual(session.activeEdit, project)
    }

    func testSession_deleteAcknowledgeOnAssignment_leavesDeleteBindingForFinish() {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .delete(project),
            activeEdit: nil,
            activeDelete: nil
        )

        session.assignIfNeeded()
        session.acknowledgeDeleteAssignment(project)
        session.finishUnacknowledgedPresentation()

        XCTAssertNil(session.pending)
        XCTAssertEqual(session.activeDelete, project)
    }

    func testSession_finishUnacknowledgedPresentation_clearsPendingWhenAssignmentNeverStuck() {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .edit(project),
            activeEdit: nil,
            activeDelete: nil
        )

        session.finishUnacknowledgedPresentation()

        XCTAssertNil(session.pending)
        XCTAssertNil(session.activeEdit)
    }

    @MainActor
    func testRunPresentationAttempts_tearsDownEditWhenNeverAcknowledged() async {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .edit(project),
            activeEdit: nil,
            activeDelete: nil
        )

        await CreatedProjectOwnerActionHandoff.runPresentationAttempts(
            session: &session,
            sleepNanoseconds: { _ in }
        )

        XCTAssertNil(session.pending)
        XCTAssertNil(session.activeEdit)
    }

    @MainActor
    func testRunPresentationAttempts_returnsEarlyWhenPendingAlreadyCleared() async {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .edit(project),
            activeEdit: nil,
            activeDelete: nil
        )
        session.assignIfNeeded()
        session.acknowledgeEditPresentation(project)

        await CreatedProjectOwnerActionHandoff.runPresentationAttempts(
            session: &session,
            sleepNanoseconds: { _ in
                XCTFail("Should not poll after pending is already cleared")
            }
        )

        // First assign inside runPresentationAttempts is a no-op (already active);
        // pending is nil so the poll loop returns before sleep / finish.
        XCTAssertNil(session.pending)
        XCTAssertEqual(session.activeEdit, project)
    }

    func testSession_retrySequence_assignAckFinishKeepsPresentedEdit() {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .edit(project),
            activeEdit: nil,
            activeDelete: nil
        )

        session.assignIfNeeded()
        session.assignIfNeeded()
        session.acknowledgeEditPresentation(project)
        session.finishUnacknowledgedPresentation()

        XCTAssertNil(session.pending)
        XCTAssertEqual(session.activeEdit, project)
    }

    func testSession_retrySequence_assignWithoutAckFinishClearsStuckEdit() {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .edit(project),
            activeEdit: nil,
            activeDelete: nil
        )

        session.assignIfNeeded()
        session.assignIfNeeded()
        session.finishUnacknowledgedPresentation()

        XCTAssertNil(session.pending)
        XCTAssertNil(session.activeEdit)
    }
}
