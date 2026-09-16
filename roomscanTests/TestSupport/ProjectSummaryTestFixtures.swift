//
//  ProjectSummaryTestFixtures.swift
//  roomscanTests
//

@testable import roomscan
import Foundation

extension ProjectSummary {
    /// Shared fixture for unit tests that need a stable `ProjectSummary`.
    static func testFixture(
        id: String = "project-1",
        revision: Int = 1,
        name: String = "Office",
        ownerName: String = "Owner",
        description: String = "Desc",
        roomScans: [RoomScanSummary] = [],
        scanCount: Int = 0
    ) -> ProjectSummary {
        ProjectSummary(
            id: id,
            revision: revision,
            name: name,
            ownerName: ownerName,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            description: description,
            roomScans: roomScans,
            scanCount: scanCount
        )
    }
}
