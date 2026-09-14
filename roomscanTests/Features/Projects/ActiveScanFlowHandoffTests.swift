//
//  ActiveScanFlowHandoffTests.swift
//  roomscanTests
//

@testable import roomscan
import XCTest

final class ActiveScanFlowHandoffTests: XCTestCase {
    /// Reading the pending flow does not clear it, so a dropped presentation can be retried.
    func testFlowAwaitingPresentation_keepsPendingUntilCoverAppears() {
        let flow = ActiveScanFlow(sourceProjectID: "project-1")
        var pending: ActiveScanFlow? = flow

        let awaiting = ActiveScanFlowHandoff.flowAwaitingPresentation(pending)

        XCTAssertEqual(awaiting?.id, flow.id)
        XCTAssertEqual(awaiting?.sourceProjectID, "project-1")
        XCTAssertEqual(pending?.id, flow.id)
    }

    /// With no pending flow, there is nothing to present.
    func testFlowAwaitingPresentation_nilPending_returnsNil() {
        let awaiting = ActiveScanFlowHandoff.flowAwaitingPresentation(nil)

        XCTAssertNil(awaiting)
    }

    /// The pending request is cleared only after the matching cover appears.
    func testAcknowledgePresented_clearsMatchingPendingFlow() {
        let flow = ActiveScanFlow(sourceProjectID: "project-1")
        var pending: ActiveScanFlow? = flow

        ActiveScanFlowHandoff.acknowledgePresented(flow, pending: &pending)

        XCTAssertNil(pending)
    }

    /// A different presented cover must not drop an Add Scan request that has not appeared yet.
    func testAcknowledgePresented_ignoresDifferentFlow() {
        let pendingFlow = ActiveScanFlow(sourceProjectID: "project-1")
        var pending: ActiveScanFlow? = pendingFlow

        ActiveScanFlowHandoff.acknowledgePresented(
            ActiveScanFlow(sourceProjectID: "project-2"),
            pending: &pending
        )

        XCTAssertEqual(pending?.id, pendingFlow.id)
    }

    /// After detail dismiss, a pending Add Scan is assigned when no scan cover is active.
    func testFlowToAssign_presentsPendingWhenScanCoverIsNotActive() {
        let pending = ActiveScanFlow(sourceProjectID: "project-1")

        let flow = ActiveScanFlowHandoff.flowToAssign(pending: pending, active: nil)

        XCTAssertEqual(flow?.id, pending.id)
        XCTAssertEqual(flow?.sourceProjectID, "project-1")
    }

    /// A rejected presentation can be assigned again because pending is still held.
    func testFlowToAssign_retriesWhenActiveCoverWasCleared() {
        let pending = ActiveScanFlow(sourceProjectID: "project-1")

        XCTAssertNil(ActiveScanFlowHandoff.flowToAssign(pending: pending, active: pending))

        let retry = ActiveScanFlowHandoff.flowToAssign(pending: pending, active: nil)

        XCTAssertEqual(retry?.id, pending.id)
        XCTAssertEqual(retry?.sourceProjectID, "project-1")
    }

    /// Does not reassign a scan cover that is already presenting the pending request.
    func testFlowToAssign_skipsWhenMatchingCoverIsAlreadyActive() {
        let pending = ActiveScanFlow(sourceProjectID: "project-1")

        let flow = ActiveScanFlowHandoff.flowToAssign(pending: pending, active: pending)

        XCTAssertNil(flow)
    }
}
