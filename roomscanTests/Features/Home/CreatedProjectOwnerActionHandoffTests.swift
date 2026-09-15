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

    @MainActor
    func testRunPresentationAttempts_doesNotClearDuringDismissGracePeriod() async {
        let result = await runEditPresentationAttempts(
            acknowledgeAfterPolls: CreatedProjectOwnerActionHandoff.retriggerGracePollCount
        )

        XCTAssertEqual(result.pollCount, CreatedProjectOwnerActionHandoff.retriggerGracePollCount)
        XCTAssertEqual(result.assignCount, 1)
        XCTAssertEqual(result.clearCount, 0)
        XCTAssertNil(result.session.pending)
        XCTAssertEqual(result.session.activeEdit, project)
    }

    @MainActor
    func testRunPresentationAttempts_retriggersOnlyAfterDismissGraceExpires() async {
        let grace = CreatedProjectOwnerActionHandoff.retriggerGracePollCount
        // Extra sleep is the clear→reassign gap; ack on the wait after reassign.
        let result = await runEditPresentationAttempts(acknowledgeAfterPolls: grace + 2)

        XCTAssertEqual(result.pollCount, grace + 2)
        XCTAssertEqual(result.assignCount, 2)
        XCTAssertEqual(result.clearCount, 1)
        XCTAssertNil(result.session.pending)
        XCTAssertEqual(result.session.activeEdit, project)
    }

    /// Shared harness for grace-period timing tests.
    @MainActor
    private func runEditPresentationAttempts(
        acknowledgeAfterPolls: Int
    ) async -> (
        session: CreatedProjectOwnerActionHandoffSession,
        clearCount: Int,
        assignCount: Int,
        pollCount: Int
    ) {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .edit(project),
            activeEdit: nil,
            activeDelete: nil
        )
        var clearCount = 0
        var assignCount = 0
        var pollCount = 0

        await CreatedProjectOwnerActionHandoff.runPresentationAttempts(
            load: { session },
            store: { updated in
                if updated.activeEdit == nil, session.activeEdit != nil {
                    clearCount += 1
                }
                if updated.activeEdit != nil, session.activeEdit == nil {
                    assignCount += 1
                }
                session = updated
            },
            sleepNanoseconds: { _ in
                pollCount += 1
                if pollCount == acknowledgeAfterPolls {
                    session.acknowledgeEditPresentation(self.project)
                }
            }
        )

        return (session, clearCount, assignCount, pollCount)
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

    @MainActor
    func testRunPresentationAttempts_clearsTimedOutEditBinding() async {
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

    @MainActor
    func testRunPresentationAttempts_stopsWhenIsCurrentBecomesFalse() async {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .edit(project),
            activeEdit: nil,
            activeDelete: nil
        )
        var isCurrent = true
        var storeCount = 0

        await CreatedProjectOwnerActionHandoff.runPresentationAttempts(
            load: { session },
            store: { updated in
                storeCount += 1
                session = updated
            },
            isCurrent: { isCurrent },
            sleepNanoseconds: { _ in
                isCurrent = false
            }
        )

        // First poll assigns once, then sleep invalidates the flight.
        XCTAssertEqual(storeCount, 1)
        XCTAssertEqual(session.activeEdit, project)
        XCTAssertEqual(session.pending, .edit(project))
    }

    @MainActor
    func testOverlappingFlights_staleFlightPerformsNoStore() async {
        var flight = CreatedProjectOwnerActionFlight()
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .edit(project),
            activeEdit: nil,
            activeDelete: nil
        )
        let staleGeneration = flight.begin()
        var staleStoreCount = 0

        // Newer flight supersedes before the stale loop mutates.
        _ = flight.begin()

        await CreatedProjectOwnerActionHandoff.runPresentationAttempts(
            load: { session },
            store: { updated in
                guard flight.isCurrent(staleGeneration) else { return }
                staleStoreCount += 1
                session = updated
            },
            isCurrent: { flight.isCurrent(staleGeneration) },
            sleepNanoseconds: { _ in
                XCTFail("Superseded flight should exit before sleeping")
            }
        )

        XCTAssertEqual(staleStoreCount, 0)
        XCTAssertNil(session.activeEdit)
        XCTAssertEqual(session.pending, .edit(project))
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

    func testPresentationAcknowledgment_deleteOnChangeClearsPending() {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .delete(project),
            activeEdit: nil,
            activeDelete: nil
        )
        session.assignIfNeeded()

        // Mirrors CreatedProjectOwnerActionPresentation.onChange(of: projectPendingDelete).
        session.acknowledgeDeleteAssignment(project)

        XCTAssertNil(session.pending)
        XCTAssertEqual(session.activeDelete, project)
    }
}
