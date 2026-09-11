//
//  ActiveScanFlowHandoffTests.swift
//  roomscanTests
//

@testable import roomscan
import XCTest

final class ActiveScanFlowHandoffTests: XCTestCase {
    /// Pending Add Scan keeps its source project ID and clears the pending slot.
    func testConsumePendingForPresentation_preservesSourceProjectIDAndClearsPending() {
        var pending: ActiveScanFlow? = ActiveScanFlow(sourceProjectID: "project-1")

        let flow = ActiveScanFlowHandoff.consumePendingForPresentation(&pending)

        XCTAssertEqual(flow?.sourceProjectID, "project-1")
        XCTAssertNil(pending)
    }

    /// With no pending flow, consume returns nil and leaves pending nil.
    func testConsumePendingForPresentation_nilPending_returnsNil() {
        var pending: ActiveScanFlow?

        let flow = ActiveScanFlowHandoff.consumePendingForPresentation(&pending)

        XCTAssertNil(flow)
        XCTAssertNil(pending)
    }
}
