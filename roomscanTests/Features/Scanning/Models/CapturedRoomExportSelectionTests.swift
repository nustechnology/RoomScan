//
//  CapturedRoomExportSelectionTests.swift
//  roomscanTests
//

@testable import roomscan
import XCTest

final class CapturedRoomExportSelectionTests: XCTestCase {
    func testPreferredSource_selectsLiveWhenItHasMoreSurfaces() {
        let processed = CapturedRoomContentSummary(wallCount: 2, floorCount: 1)
        let live = CapturedRoomContentSummary(wallCount: 12, floorCount: 1)

        let source = CapturedRoomExportSelection.preferredSource(
            processed: processed,
            live: live
        )

        XCTAssertEqual(source, .live)
    }

    func testPreferredSource_selectsProcessedWhenLiveIsMissingFloor() {
        let processed = CapturedRoomContentSummary(wallCount: 1, floorCount: 1)
        let live = CapturedRoomContentSummary(wallCount: 3, floorCount: 0)

        let source = CapturedRoomExportSelection.preferredSource(
            processed: processed,
            live: live
        )

        XCTAssertEqual(source, .processed)
    }

    func testPreferredSource_selectsLiveWhenProcessedIsMissingFloor() {
        let processed = CapturedRoomContentSummary(wallCount: 3, floorCount: 0)
        let live = CapturedRoomContentSummary(wallCount: 1, floorCount: 1)

        let source = CapturedRoomExportSelection.preferredSource(
            processed: processed,
            live: live
        )

        XCTAssertEqual(source, .live)
    }

    func testPreferredSource_selectsProcessedWhenLiveIsMissingWalls() {
        let processed = CapturedRoomContentSummary(wallCount: 1, floorCount: 1)
        let live = CapturedRoomContentSummary(wallCount: 0, floorCount: 3)

        let source = CapturedRoomExportSelection.preferredSource(
            processed: processed,
            live: live
        )

        XCTAssertEqual(source, .processed)
    }

    func testPreferredSource_selectsLiveWhenNeitherHasMinimalStructureAndLiveHasMoreSurfaces() {
        let processed = CapturedRoomContentSummary(wallCount: 2, floorCount: 0)
        let live = CapturedRoomContentSummary(wallCount: 12, floorCount: 0)

        let source = CapturedRoomExportSelection.preferredSource(
            processed: processed,
            live: live
        )

        XCTAssertEqual(source, .live)
    }

    func testPreferredSource_selectsProcessedWhenSurfaceCountsAreEqual() {
        let processed = CapturedRoomContentSummary(wallCount: 8, floorCount: 2)
        let live = CapturedRoomContentSummary(wallCount: 8, floorCount: 2)

        let source = CapturedRoomExportSelection.preferredSource(
            processed: processed,
            live: live
        )

        XCTAssertEqual(source, .processed)
    }

    func testPreferredSource_selectsProcessedWhenItHasMoreSurfaces() {
        let processed = CapturedRoomContentSummary(wallCount: 10, floorCount: 1, doorCount: 2)
        let live = CapturedRoomContentSummary(wallCount: 6, floorCount: 1)

        let source = CapturedRoomExportSelection.preferredSource(
            processed: processed,
            live: live
        )

        XCTAssertEqual(source, .processed)
    }

    func testPreferredSource_selectsLiveWhenProcessedIsMissing() {
        let live = CapturedRoomContentSummary(wallCount: 4, floorCount: 1)

        let source = CapturedRoomExportSelection.preferredSource(
            processed: nil,
            live: live
        )

        XCTAssertEqual(source, .live)
    }

    func testPreferredSource_selectsProcessedWhenLiveIsMissing() {
        let processed = CapturedRoomContentSummary(wallCount: 4, floorCount: 1)

        let source = CapturedRoomExportSelection.preferredSource(
            processed: processed,
            live: nil
        )

        XCTAssertEqual(source, .processed)
    }

    func testPreferredSource_returnsNilWhenBothAreMissing() {
        let source = CapturedRoomExportSelection.preferredSource(
            processed: nil,
            live: nil
        )

        XCTAssertNil(source)
    }

    func testPreferredSource_ignoresEmptySummaries() {
        let empty = CapturedRoomContentSummary()
        let live = CapturedRoomContentSummary(objectCount: 1)

        let source = CapturedRoomExportSelection.preferredSource(
            processed: empty,
            live: live
        )

        XCTAssertEqual(source, .live)
    }

    func testPreferredSource_returnsNilWhenBothSummariesAreEmpty() {
        let source = CapturedRoomExportSelection.preferredSource(
            processed: CapturedRoomContentSummary(),
            live: CapturedRoomContentSummary()
        )

        XCTAssertNil(source)
    }
}
