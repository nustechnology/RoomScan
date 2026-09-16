//
//  PresentationHandoffTests.swift
//  roomscanTests
//

@testable import roomscan
import XCTest

final class PresentationHandoffTests: XCTestCase {
    func testFlight_beginInvalidatesPriorGeneration() {
        var flight = PresentationFlight()
        let first = flight.begin()
        let second = flight.begin()

        XCTAssertTrue(flight.isCurrent(second))
        XCTAssertFalse(flight.isCurrent(first))
    }

    @MainActor
    func testPresentAfterDismiss_assignsTwiceWhenCurrent() async {
        var assignCount = 0
        var yieldCount = 0

        await PresentationHandoff.presentAfterDismiss(
            yield: { yieldCount += 1 }
        ) {
            assignCount += 1
        }

        XCTAssertEqual(yieldCount, 2)
        XCTAssertEqual(assignCount, 2)
    }

    @MainActor
    func testPresentAfterDismiss_stopsBeforeFirstAssignWhenSuperseded() async {
        var assignCount = 0
        var isCurrent = true

        await PresentationHandoff.presentAfterDismiss(
            isCurrent: { isCurrent },
            yield: { isCurrent = false }
        ) {
            assignCount += 1
        }

        XCTAssertEqual(assignCount, 0)
    }

    @MainActor
    func testPresentAfterDismiss_stopsBeforeSecondAssignWhenSupersededAfterFirst() async {
        var assignCount = 0
        var yieldCount = 0
        var isCurrent = true

        await PresentationHandoff.presentAfterDismiss(
            isCurrent: { isCurrent },
            yield: {
                yieldCount += 1
                if yieldCount == 2 {
                    isCurrent = false
                }
            }
        ) {
            assignCount += 1
        }

        XCTAssertEqual(assignCount, 1)
    }
}
