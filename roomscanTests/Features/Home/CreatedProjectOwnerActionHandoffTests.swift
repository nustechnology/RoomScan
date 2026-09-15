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

    @MainActor
    func testRunPresentationAttempts_forceReassignsEachPollUntilAcknowledged() async {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .edit(project),
            activeEdit: nil,
            activeDelete: nil
        )
        var clearThenAssignCycles = 0
        var sawClearedBinding = false
        var pollCount = 0

        await CreatedProjectOwnerActionHandoff.runPresentationAttempts(
            load: { session },
            store: { updated in
                if updated.activeEdit == nil, session.pending != nil {
                    sawClearedBinding = true
                }
                if updated.activeEdit != nil, sawClearedBinding {
                    clearThenAssignCycles += 1
                    sawClearedBinding = false
                }
                session = updated
            },
            sleepNanoseconds: { _ in
                pollCount += 1
                // Allow at least one full clear→assign→sleep cycle before acknowledging.
                if pollCount == 2 {
                    session.acknowledgeEditPresentation(self.project)
                }
            }
        )

        XCTAssertEqual(pollCount, 2)
        XCTAssertGreaterThanOrEqual(clearThenAssignCycles, 2)
        XCTAssertNil(session.pending)
        XCTAssertEqual(session.activeEdit, project)
    }

    @MainActor
    func testRunPresentationAttempts_tearsDownEditWhenNeverAcknowledged() async {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .edit(project),
            activeEdit: nil,
            activeDelete: nil
        )

        await CreatedProjectOwnerActionHandoff.runPresentationAttempts(
            load: { session },
            store: { session = $0 },
            sleepNanoseconds: { _ in }
        )

        XCTAssertNil(session.pending)
        XCTAssertNil(session.activeEdit)
    }

    @MainActor
    func testRunPresentationAttempts_observesLiveAcknowledgmentDuringPoll() async {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .edit(project),
            activeEdit: nil,
            activeDelete: nil
        )
        var pollCount = 0

        await CreatedProjectOwnerActionHandoff.runPresentationAttempts(
            load: { session },
            store: { session = $0 },
            sleepNanoseconds: { _ in
                pollCount += 1
                session.acknowledgeEditPresentation(self.project)
            }
        )

        XCTAssertEqual(pollCount, 1)
        XCTAssertNil(session.pending)
        XCTAssertEqual(session.activeEdit, project)
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
            load: { session },
            store: { session = $0 },
            sleepNanoseconds: { _ in
                XCTFail("Should not poll after pending is already cleared")
            }
        )

        XCTAssertNil(session.pending)
        XCTAssertEqual(session.activeEdit, project)
    }

    @MainActor
    func testRunPresentationAttempts_deleteAcknowledgedViaLiveStoreSurvivesFinish() async {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .delete(project),
            activeEdit: nil,
            activeDelete: nil
        )

        await CreatedProjectOwnerActionHandoff.runPresentationAttempts(
            load: { session },
            store: { updated in
                session = updated
                if let project = updated.activeDelete, updated.pending != nil {
                    session.acknowledgeDeleteAssignment(project)
                }
            },
            sleepNanoseconds: { _ in
                XCTFail("Delete acknowledgment on store should clear pending before poll sleep")
            }
        )

        XCTAssertNil(session.pending)
        XCTAssertEqual(session.activeDelete, project)
    }
}
