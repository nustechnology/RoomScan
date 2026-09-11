//
//  ActiveScanFlowHandoffTests.swift
//  roomscanTests
//

@testable import roomscan
import XCTest

final class ActiveScanFlowHandoffTests: XCTestCase {
    func testConsumePendingForPresentation_preservesSourceProjectIDAndClearsPending() {
        var pending: ActiveScanFlow? = ActiveScanFlow(sourceProjectID: "project-1")

        let flow = ActiveScanFlowHandoff.consumePendingForPresentation(&pending)

        XCTAssertEqual(flow?.sourceProjectID, "project-1")
        XCTAssertNil(pending)
    }

    func testConsumePendingForPresentation_nilPending_returnsNil() {
        var pending: ActiveScanFlow?

        let flow = ActiveScanFlowHandoff.consumePendingForPresentation(&pending)

        XCTAssertNil(flow)
        XCTAssertNil(pending)
    }
}
