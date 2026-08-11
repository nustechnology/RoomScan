//
//  ProjectScansContentStateTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

struct ProjectScansContentStateTests {
    @Test func emptyWhenCountAndLocalScansAreZero() {
        let project = ProjectSummary(id: "p1", name: "Empty", roomScans: [], scanCount: 0)
        #expect(project.scansContentState == .empty)
    }

    @Test func remoteOnlyWhenServerCountExistsWithoutLocalScans() {
        let project = ProjectSummary(id: "p1", name: "Remote", roomScans: [], scanCount: 3)
        #expect(project.scansContentState == .remoteOnly)
    }

    @Test func localWhenRoomScansArePresent() {
        let scan = RoomScanSummary(
            id: "s1",
            name: "Living Room",
            createdAt: Date(timeIntervalSince1970: 1_000),
            thumbnailName: "thumbnail-0",
            syncStatus: .synced,
            notes: []
        )
        let project = ProjectSummary(id: "p1", name: "Local", roomScans: [scan], scanCount: 1)
        #expect(project.scansContentState == .local)
    }
}
