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

    func testSession_assignIfNeeded_editKeepsPendingUntilAcknowledged() {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .edit(project),
            activeEdit: nil,
            activeDelete: nil
        )

        session.assignIfNeeded()

        XCTAssertEqual(session.activeEdit, project)
        XCTAssertEqual(session.pending, .edit(project))
    }

    func testSession_assignIfNeeded_deleteKeepsPendingUntilAcknowledged() {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .delete(project),
            activeEdit: nil,
            activeDelete: nil
        )

        session.assignIfNeeded()

        XCTAssertEqual(session.activeDelete, project)
        XCTAssertEqual(session.pending, .delete(project))
    }

    func testSession_assignIfNeeded_secondPassRetriesSwallowedEdit() {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .edit(project),
            activeEdit: nil,
            activeDelete: nil
        )

        session.assignIfNeeded()
        // Simulate SwiftUI rejecting the first fullScreenCover assignment.
        session.activeEdit = nil

        session.assignIfNeeded()

        XCTAssertEqual(session.activeEdit, project)
        XCTAssertEqual(session.pending, .edit(project))
    }

    func testSession_assignIfNeeded_secondPassRetriesSwallowedDelete() {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .delete(project),
            activeEdit: nil,
            activeDelete: nil
        )

        session.assignIfNeeded()
        // Simulate SwiftUI rejecting the first alert presentation.
        session.activeDelete = nil

        session.assignIfNeeded()

        XCTAssertEqual(session.activeDelete, project)
        XCTAssertEqual(session.pending, .delete(project))
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

    func testSession_snapshotCarriesAllBindings() {
        let session = CreatedProjectOwnerActionHandoffSession.snapshot(
            pending: .edit(project),
            activeEdit: otherProject,
            activeDelete: nil
        )

        XCTAssertEqual(session.pending, .edit(project))
        XCTAssertEqual(session.activeEdit, otherProject)
        XCTAssertNil(session.activeDelete)
    }

    func testSession_dropUnpresentedEditRequest_clearsSwallowedEdit() {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .edit(project),
            activeEdit: nil,
            activeDelete: nil
        )

        session.dropUnpresentedEditRequest()

        XCTAssertNil(session.pending)
    }

    func testSession_dropUnpresentedEditRequest_keepsActiveCoverOrDelete() {
        var activeSession = CreatedProjectOwnerActionHandoffSession(
            pending: .edit(project),
            activeEdit: project,
            activeDelete: nil
        )
        activeSession.dropUnpresentedEditRequest()
        XCTAssertEqual(activeSession.pending, .edit(project))

        var deleteSession = CreatedProjectOwnerActionHandoffSession(
            pending: .delete(project),
            activeEdit: nil,
            activeDelete: nil
        )
        deleteSession.dropUnpresentedEditRequest()
        XCTAssertEqual(deleteSession.pending, .delete(project))
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

    func testSession_abandonUnacknowledgedPresentation_clearsAssignedDeleteConfirmation() {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .delete(project),
            activeEdit: nil,
            activeDelete: project
        )

        session.abandonUnacknowledgedPresentation()

        XCTAssertNil(session.pending)
        XCTAssertNil(session.activeDelete)
    }

    func testPresentationAcknowledgment_editOnAppearClearsPending() {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .edit(project),
            activeEdit: project,
            activeDelete: nil
        )

        // Mirrors ProjectOwnerActionPresentation.onAppear wiring.
        session.acknowledgeEditPresentation(project)

        XCTAssertNil(session.pending)
        XCTAssertEqual(session.activeEdit, project)
    }

    func testPresentationAcknowledgment_deleteUserDismissClearsPending() {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .delete(project),
            activeEdit: nil,
            activeDelete: project
        )

        // Mirrors ProjectOwnerActionPresentation.onUserDismissed wiring.
        session.acknowledgeDeletePresentation(project)

        XCTAssertNil(session.pending)
        XCTAssertEqual(session.activeDelete, project)
    }

    func testPresentationAcknowledgment_deleteTeardownClearsPendingWithoutButton() {
        var pending: CreatedProjectOwnerAction? = .delete(project)
        var activeDelete: ProjectSummary? = project

        // Mirrors ProjectOwnerActionPresentation: SwiftUI can tear the alert down
        // (isPresented false) without a button action, and that path must still clear pending
        // so a later created-detail dismiss cannot re-present the stale confirmation.
        ProjectDeleteConfirmationActions.handleIsPresentedChange(
            false,
            projectPendingDelete: &activeDelete,
            onUserDismissed: {
                guard case .delete(let project) = pending else { return }
                pending = CreatedProjectOwnerActionHandoff.pendingAfterAcknowledging(
                    .delete(project),
                    pending: pending
                )
            }
        )

        XCTAssertNil(activeDelete)
        XCTAssertNil(pending)
    }
}
