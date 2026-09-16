//
//  CreatedProjectOwnerActionHandoffRunTests.swift
//  roomscanTests
//

@testable import roomscan
import XCTest

final class CreatedProjectOwnerActionHandoffRunTests: XCTestCase {
    private let project = ProjectSummary.testFixture()

    @MainActor
    func testPresentAfterDetailDismiss_assignsEditOnceWhenAcknowledgedAfterFirstAssign() async {
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
                if yieldCount == 2 {
                    // Cover appeared between the two assigns (clears pending).
                    session.acknowledgeEditPresentation(self.project)
                }
            }
        )

        XCTAssertEqual(yieldCount, 2)
        XCTAssertEqual(assignCount, 1)
        XCTAssertNil(session.pending)
        XCTAssertEqual(session.activeEdit, project)
    }

    @MainActor
    func testPresentAfterDetailDismiss_retriesEditWhenFirstAssignmentIsSwallowed() async {
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
                if yieldCount == 2, session.activeEdit != nil {
                    // Simulate SwiftUI clearing a rejected fullScreenCover item.
                    session.activeEdit = nil
                }
            }
        )

        XCTAssertEqual(yieldCount, 2)
        XCTAssertEqual(assignCount, 2)
        XCTAssertEqual(session.activeEdit, project)
        XCTAssertEqual(session.pending, .edit(project))
    }

    @MainActor
    func testPresentAfterDetailDismiss_deleteAcknowledgesWithoutTeardown() async {
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: .delete(project),
            activeEdit: nil,
            activeDelete: nil
        )
        var clearCount = 0
        var assignCount = 0

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
            yield: {}
        )

        XCTAssertEqual(assignCount, 1)
        XCTAssertEqual(clearCount, 0)
        XCTAssertNil(session.pending)
        XCTAssertEqual(session.activeDelete, project)
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
}
