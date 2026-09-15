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

    func testActionAwaitingPresentation_keepsPendingUntilAcknowledged() {
        let pending: CreatedProjectOwnerAction? = .edit(project)

        let awaiting = CreatedProjectOwnerActionHandoff.actionAwaitingPresentation(pending)

        XCTAssertEqual(awaiting, .edit(project))
    }

    func testActionToAssign_presentsPendingEditWhenEditCoverIsNotActive() {
        let action = CreatedProjectOwnerActionHandoff.actionToAssign(
            pending: .edit(project),
            activeEdit: nil,
            activeDelete: nil
        )

        XCTAssertEqual(action, .edit(project))
    }

    func testActionToAssign_presentsPendingDeleteWhenDeleteAlertIsNotActive() {
        let action = CreatedProjectOwnerActionHandoff.actionToAssign(
            pending: .delete(project),
            activeEdit: nil,
            activeDelete: nil
        )

        XCTAssertEqual(action, .delete(project))
    }

    func testActionToAssign_skipsWhenMatchingEditCoverIsAlreadyActive() {
        let action = CreatedProjectOwnerActionHandoff.actionToAssign(
            pending: .edit(project),
            activeEdit: project,
            activeDelete: nil
        )

        XCTAssertNil(action)
    }

    func testActionToAssign_skipsWhenMatchingDeleteAlertIsAlreadyActive() {
        let action = CreatedProjectOwnerActionHandoff.actionToAssign(
            pending: .delete(project),
            activeEdit: nil,
            activeDelete: project
        )

        XCTAssertNil(action)
    }

    func testActionToAssign_retriesWhenActiveEditWasCleared() {
        let pending: CreatedProjectOwnerAction = .edit(project)

        XCTAssertNil(
            CreatedProjectOwnerActionHandoff.actionToAssign(
                pending: pending,
                activeEdit: project,
                activeDelete: nil
            )
        )

        let retry = CreatedProjectOwnerActionHandoff.actionToAssign(
            pending: pending,
            activeEdit: nil,
            activeDelete: nil
        )

        XCTAssertEqual(retry, .edit(project))
    }

    func testAcknowledgePresented_clearsMatchingPendingAction() {
        let pending: CreatedProjectOwnerAction? = .delete(project)

        let remaining = CreatedProjectOwnerActionHandoff.pendingAfterAcknowledging(
            .delete(project),
            pending: pending
        )

        XCTAssertNil(remaining)
    }

    func testAcknowledgePresented_ignoresDifferentActionKind() {
        let pending: CreatedProjectOwnerAction? = .edit(project)

        let remaining = CreatedProjectOwnerActionHandoff.pendingAfterAcknowledging(
            .delete(project),
            pending: pending
        )

        XCTAssertEqual(remaining, .edit(project))
    }

    func testPresentationTarget_mapsPendingEditToEditCover() {
        let target = CreatedProjectOwnerActionHandoff.presentationTarget(
            pending: .edit(project),
            activeEdit: nil,
            activeDelete: nil
        )

        XCTAssertEqual(target, .edit(project))
    }

    func testPresentationTarget_mapsPendingDeleteToDeleteAlert() {
        let target = CreatedProjectOwnerActionHandoff.presentationTarget(
            pending: .delete(project),
            activeEdit: nil,
            activeDelete: nil
        )

        XCTAssertEqual(target, .delete(project))
    }

    func testPresentationTarget_skipsWhenMatchingPresentationIsAlreadyActive() {
        let editTarget = CreatedProjectOwnerActionHandoff.presentationTarget(
            pending: .edit(project),
            activeEdit: project,
            activeDelete: nil
        )
        let deleteTarget = CreatedProjectOwnerActionHandoff.presentationTarget(
            pending: .delete(project),
            activeEdit: nil,
            activeDelete: project
        )

        XCTAssertNil(editTarget)
        XCTAssertNil(deleteTarget)
    }

    func testPresentationLifecycle_clearsPendingAfterEditAcknowledged() {
        var pending: CreatedProjectOwnerAction? = .edit(project)

        let target = CreatedProjectOwnerActionHandoff.presentationTarget(
            pending: pending,
            activeEdit: nil,
            activeDelete: nil
        )
        XCTAssertEqual(target, .edit(project))

        XCTAssertNil(
            CreatedProjectOwnerActionHandoff.presentationTarget(
                pending: pending,
                activeEdit: project,
                activeDelete: nil
            )
        )

        pending = CreatedProjectOwnerActionHandoff.pendingAfterAcknowledging(
            .edit(project),
            pending: pending
        )
        XCTAssertNil(pending)

        XCTAssertNil(
            CreatedProjectOwnerActionHandoff.presentationTarget(
                pending: pending,
                activeEdit: project,
                activeDelete: nil
            )
        )
    }

    func testPresentationLifecycle_clearsPendingAfterDeleteAcknowledged() {
        var pending: CreatedProjectOwnerAction? = .delete(project)

        let target = CreatedProjectOwnerActionHandoff.presentationTarget(
            pending: pending,
            activeEdit: nil,
            activeDelete: nil
        )
        XCTAssertEqual(target, .delete(project))

        XCTAssertNil(
            CreatedProjectOwnerActionHandoff.presentationTarget(
                pending: pending,
                activeEdit: nil,
                activeDelete: project
            )
        )

        pending = CreatedProjectOwnerActionHandoff.pendingAfterAcknowledging(
            .delete(project),
            pending: pending
        )
        XCTAssertNil(pending)
    }

    func testPendingAfterPresentationAttempts_clearsWhenNothingBecameActive() {
        let remaining = CreatedProjectOwnerActionHandoff.pendingAfterPresentationAttempts(
            pending: .edit(project),
            activeEdit: nil,
            activeDelete: nil
        )

        XCTAssertNil(remaining)
    }

    func testPendingAfterPresentationAttempts_keepsPendingWhileMatchingEditIsActive() {
        let remaining = CreatedProjectOwnerActionHandoff.pendingAfterPresentationAttempts(
            pending: .edit(project),
            activeEdit: project,
            activeDelete: nil
        )

        XCTAssertEqual(remaining, .edit(project))
    }

    func testPendingAfterPresentationAttempts_keepsPendingWhileMatchingDeleteIsActive() {
        let remaining = CreatedProjectOwnerActionHandoff.pendingAfterPresentationAttempts(
            pending: .delete(project),
            activeEdit: nil,
            activeDelete: project
        )

        XCTAssertEqual(remaining, .delete(project))
    }
}
