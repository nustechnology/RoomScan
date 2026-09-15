//
//  CreatedProjectOwnerActionHandoffRunTests.swift
//  roomscanTests
//

@testable import roomscan
import XCTest

private struct EditPresentationAttemptResult {
    let session: CreatedProjectOwnerActionHandoffSession
    let clearCount: Int
    let assignCount: Int
    let pollCount: Int
}

final class CreatedProjectOwnerActionHandoffRunTests: XCTestCase {
    private let project = ProjectSummary.testFixture()

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
    func testRunPresentationAttempts_deleteSettlesAfterOneRetriggerWithoutExternalAck() async {
        let grace = CreatedProjectOwnerActionHandoff.retriggerGracePollCount
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .delete(project),
            activeEdit: nil,
            activeDelete: nil
        )
        var clearCount = 0
        var assignCount = 0
        var pollCount = 0

        await CreatedProjectOwnerActionHandoff.runPresentationAttempts(
            load: { session },
            store: { updated in
                if updated.activeDelete == nil, session.activeDelete != nil {
                    clearCount += 1
                }
                if updated.activeDelete != nil, session.activeDelete == nil {
                    assignCount += 1
                }
                session = updated
            },
            sleepNanoseconds: { _ in
                pollCount += 1
            }
        )

        // grace waits + clear-gap sleep + grace waits, then settle-ack (no second clear).
        XCTAssertEqual(pollCount, grace * 2 + 1)
        XCTAssertEqual(assignCount, 2)
        XCTAssertEqual(clearCount, 1)
        XCTAssertNil(session.pending)
        XCTAssertEqual(session.activeDelete, project)
    }

    @MainActor
    func testRunPresentationAttempts_lateAckDuringFinalSleepKeepsActiveEdit() async {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .edit(project),
            activeEdit: nil,
            activeDelete: nil
        )
        var pollCount = 0
        let polls = CreatedProjectOwnerActionHandoff.acknowledgmentPollCount
        let grace = CreatedProjectOwnerActionHandoff.retriggerGracePollCount
        // One sleep per poll iteration, plus one clear-gap sleep per retrigger.
        let lastSleep = polls + (polls - grace) / grace

        await CreatedProjectOwnerActionHandoff.runPresentationAttempts(
            load: { session },
            store: { session = $0 },
            sleepNanoseconds: { _ in
                pollCount += 1
                if pollCount == lastSleep {
                    session.acknowledgeEditPresentation(self.project)
                }
            }
        )

        XCTAssertEqual(pollCount, lastSleep)
        XCTAssertNil(session.pending)
        XCTAssertEqual(session.activeEdit, project)
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

    /// Shared harness for grace-period timing tests.
    @MainActor
    private func runEditPresentationAttempts(
        acknowledgeAfterPolls: Int
    ) async -> EditPresentationAttemptResult {
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

        return EditPresentationAttemptResult(
            session: session,
            clearCount: clearCount,
            assignCount: assignCount,
            pollCount: pollCount
        )
    }
}
