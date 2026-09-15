//
//  ProjectDeleteConfirmationActionsTests.swift
//  roomscanTests
//

@testable import roomscan
import XCTest

final class ProjectDeleteConfirmationActionsTests: XCTestCase {
    private let project = ProjectSummary.testFixture()

    func testHandleConfirm_clearsPendingThenInvokesCallbackWithPresentedID() {
        var pending: ProjectSummary? = project
        var confirmedID: ProjectSummary.ID?

        ProjectDeleteConfirmationActions.handleConfirm(
            project: project,
            projectPendingDelete: &pending,
            onConfirmDelete: { confirmedID = $0 }
        )

        XCTAssertNil(pending)
        XCTAssertEqual(confirmedID, "project-1")
    }

    func testHandleCancel_clearsPendingWithoutInvokingCallback() {
        var pending: ProjectSummary? = project
        var confirmedID: ProjectSummary.ID?
        var didDismiss = false

        ProjectDeleteConfirmationActions.handleCancel(
            projectPendingDelete: &pending,
            onUserDismissed: { didDismiss = true }
        )

        XCTAssertNil(pending)
        XCTAssertNil(confirmedID)
        XCTAssertTrue(didDismiss)
    }

    func testHandleConfirm_notifiesUserDismissedBeforeDeleteCallback() {
        var pending: ProjectSummary? = project
        var sequence: [String] = []

        ProjectDeleteConfirmationActions.handleConfirm(
            project: project,
            projectPendingDelete: &pending,
            onConfirmDelete: { _ in sequence.append("confirm") },
            onUserDismissed: { sequence.append("dismiss") }
        )

        XCTAssertEqual(sequence, ["dismiss", "confirm"])
        XCTAssertNil(pending)
    }

    func testHandleIsPresentedChange_falseClearsPending() {
        var pending: ProjectSummary? = project

        ProjectDeleteConfirmationActions.handleIsPresentedChange(
            false,
            projectPendingDelete: &pending
        )

        XCTAssertNil(pending)
    }

    func testHandleIsPresentedChange_trueLeavesPending() {
        var pending: ProjectSummary? = project

        ProjectDeleteConfirmationActions.handleIsPresentedChange(
            true,
            projectPendingDelete: &pending
        )

        XCTAssertEqual(pending, project)
    }

    func testHandleConfirm_usesPresentedProjectIDEvenIfBindingAlreadyCleared() {
        var pending: ProjectSummary? = project
        var confirmedID: ProjectSummary.ID?
        let presented = project

        pending = nil
        ProjectDeleteConfirmationActions.handleConfirm(
            project: presented,
            projectPendingDelete: &pending,
            onConfirmDelete: { confirmedID = $0 }
        )

        XCTAssertEqual(confirmedID, presented.id)
        XCTAssertNil(pending)
    }
}
