//
//  CreatedProjectOwnerActionHandoffRunTests.swift
//  roomscanTests
//

@testable import roomscan
import XCTest

private struct EditHandoffRunResult {
    let session: CreatedProjectOwnerActionHandoffSession
    let assignCount: Int
    let yieldCount: Int
}

private struct DeleteHandoffRunResult {
    let session: CreatedProjectOwnerActionHandoffSession
    let assignCount: Int
    let clearCount: Int
    let yieldCount: Int
}

final class CreatedProjectOwnerActionHandoffRunTests: XCTestCase {
    private let project = ProjectSummary.testFixture()

    @MainActor
    func testPresentAfterDetailDismiss_assignsEditOnceWhenAcknowledgedAfterFirstAssign() async {
        let result = await runEditHandoff { session, yieldCount in
            if yieldCount == 2 {
                // Cover appeared between the two assigns (clears pending).
                session.acknowledgeEditPresentation(self.project)
            }
        }

        XCTAssertEqual(result.yieldCount, 2)
        XCTAssertEqual(result.assignCount, 1)
        XCTAssertNil(result.session.pending)
        XCTAssertEqual(result.session.activeEdit, project)
    }

    @MainActor
    func testPresentAfterDetailDismiss_retriesEditWhenFirstAssignmentIsSwallowed() async {
        let result = await runEditHandoff { session, yieldCount in
            if yieldCount == 2, session.activeEdit != nil {
                // Simulate SwiftUI clearing a rejected fullScreenCover item.
                session.activeEdit = nil
            }
        }

        XCTAssertEqual(result.yieldCount, 2)
        XCTAssertEqual(result.assignCount, 2)
        XCTAssertEqual(result.session.activeEdit, project)
        XCTAssertEqual(result.session.pending, .edit(project))
    }

    @MainActor
    func testPresentAfterDetailDismiss_deleteAssignsWithoutTeardownAndKeepsPending() async {
        let result = await runDeleteHandoff { _, _ in }

        XCTAssertEqual(result.yieldCount, 2)
        XCTAssertEqual(result.assignCount, 1)
        XCTAssertEqual(result.clearCount, 0)
        XCTAssertEqual(result.session.pending, .delete(project))
        XCTAssertEqual(result.session.activeDelete, project)
    }

    @MainActor
    func testPresentAfterDetailDismiss_retriesDeleteWhenFirstAssignmentIsSwallowed() async {
        let result = await runDeleteHandoff { session, yieldCount in
            if yieldCount == 2, session.activeDelete != nil {
                // Simulate SwiftUI clearing a rejected alert presentation.
                session.activeDelete = nil
            }
        }

        XCTAssertEqual(result.yieldCount, 2)
        XCTAssertEqual(result.assignCount, 2)
        XCTAssertEqual(result.clearCount, 0)
        XCTAssertEqual(result.session.activeDelete, project)
        XCTAssertEqual(result.session.pending, .delete(project))
    }

    @MainActor
    func testPresentAfterDetailDismiss_stopsWhenIsCurrentBecomesFalseBeforeFirstAssign() async {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .edit(project),
            activeEdit: nil,
            activeDelete: nil
        )
        var isCurrent = true
        var storeCount = 0

        await CreatedProjectOwnerActionHandoff.presentAfterDetailDismiss(
            load: { session },
            store: { updated in
                storeCount += 1
                session = updated
            },
            isCurrent: { isCurrent },
            yield: {
                isCurrent = false
            }
        )

        XCTAssertEqual(storeCount, 0)
        XCTAssertNil(session.activeEdit)
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

        // Newer flight supersedes before the stale handoff mutates.
        _ = flight.begin()

        await CreatedProjectOwnerActionHandoff.presentAfterDetailDismiss(
            load: { session },
            store: { updated in
                guard flight.isCurrent(staleGeneration) else { return }
                staleStoreCount += 1
                session = updated
            },
            isCurrent: { flight.isCurrent(staleGeneration) },
            yield: {}
        )

        XCTAssertEqual(staleStoreCount, 0)
        XCTAssertNil(session.activeEdit)
        XCTAssertEqual(session.pending, .edit(project))
    }

    /// Shared harness for edit handoff sequencing tests.
    @MainActor
    private func runEditHandoff(
        onYield: @MainActor (inout CreatedProjectOwnerActionHandoffSession, Int) -> Void
    ) async -> EditHandoffRunResult {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .edit(project),
            activeEdit: nil,
            activeDelete: nil
        )
        var assignCount = 0
        var yieldCount = 0

        await CreatedProjectOwnerActionHandoff.presentAfterDetailDismiss(
            load: { session },
            store: { updated in
                if updated.activeEdit != nil, session.activeEdit == nil {
                    assignCount += 1
                }
                session = updated
            },
            yield: {
                yieldCount += 1
                onYield(&session, yieldCount)
            }
        )

        return EditHandoffRunResult(
            session: session,
            assignCount: assignCount,
            yieldCount: yieldCount
        )
    }

    /// Shared harness for delete handoff sequencing tests.
    @MainActor
    private func runDeleteHandoff(
        onYield: @MainActor (inout CreatedProjectOwnerActionHandoffSession, Int) -> Void
    ) async -> DeleteHandoffRunResult {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .delete(project),
            activeEdit: nil,
            activeDelete: nil
        )
        var assignCount = 0
        var clearCount = 0
        var yieldCount = 0

        await CreatedProjectOwnerActionHandoff.presentAfterDetailDismiss(
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
            yield: {
                yieldCount += 1
                onYield(&session, yieldCount)
            }
        )

        return DeleteHandoffRunResult(
            session: session,
            assignCount: assignCount,
            clearCount: clearCount,
            yieldCount: yieldCount
        )
    }
}
