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
    func testHomeViewGlue_deleteHandoffPresentsAfterDetailDismissThenAbandonsOnTabChange() async {
        var flight = CreatedProjectOwnerActionFlight()
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: nil,
            activeEdit: nil,
            activeDelete: nil
        )

        // beginOwnerActionAfterCreatedDetail while detail is up: invalidate, stage, dismiss.
        _ = flight.begin()
        session.begin(.delete(project))
        XCTAssertEqual(session.pending, .delete(project))

        // selectedCreatedProject onDismiss -> presentPendingOwnerActionAfterCreatedDetailDismiss.
        let generation = flight.begin()
        await CreatedProjectOwnerActionHandoff.presentAfterDetailDismiss(
            load: { session },
            store: { updated in
                guard flight.isCurrent(generation) else { return }
                session = updated
            },
            isCurrent: { flight.isCurrent(generation) },
            yield: {}
        )
        XCTAssertEqual(session.activeDelete, project)
        XCTAssertEqual(session.pending, .delete(project))

        // selectedTab onChange -> cancelUnacknowledgedOwnerActionPresentation.
        _ = flight.begin()
        session.abandonUnacknowledgedPresentation()
        XCTAssertNil(session.pending)
        XCTAssertNil(session.activeDelete)
    }

    @MainActor
    func testHomeViewGlue_beginWithoutDetailCoverPresentsImmediately() async {
        var flight = CreatedProjectOwnerActionFlight()
        var session = CreatedProjectOwnerActionHandoffSession(
            pending: nil,
            activeEdit: nil,
            activeDelete: nil
        )

        // beginOwnerActionAfterCreatedDetail when selectedCreatedProject == nil.
        _ = flight.begin()
        session.begin(.edit(project))

        // Falls through to presentPendingOwnerActionAfterCreatedDetailDismiss directly.
        let generation = flight.begin()
        await CreatedProjectOwnerActionHandoff.presentAfterDetailDismiss(
            load: { session },
            store: { updated in
                guard flight.isCurrent(generation) else { return }
                session = updated
            },
            isCurrent: { flight.isCurrent(generation) },
            yield: {}
        )

        XCTAssertEqual(session.activeEdit, project)
        XCTAssertEqual(session.pending, .edit(project))
    }

    @MainActor
    func testHomeViewGlue_isPresentedTeardownDropsPendingSoLaterDismissDoesNotRepresent() async {
        var pending: CreatedProjectOwnerAction? = .delete(project)
        var activeDelete: ProjectSummary? = project

        // SwiftUI tears the alert down without Cancel/Confirm.
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

        var session = CreatedProjectOwnerActionHandoffSession(
            pending: pending,
            activeEdit: nil,
            activeDelete: activeDelete
        )

        // A later created-detail dismiss must not resurrect the abandoned delete.
        await CreatedProjectOwnerActionHandoff.presentAfterDetailDismiss(
            load: { session },
            store: { session = $0 },
            yield: {}
        )
        XCTAssertNil(session.activeDelete)
        XCTAssertNil(session.pending)
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
