//
//  MockProjectsFixtures.swift
//  roomscan
//

import Foundation

extension MockProjectsService {
    nonisolated static func makeSeedProjects() -> [ProjectSummary] {
        let baseDate = fixtureBaseDate
        return (1...14).map { index in
            ProjectSummary(
                id: "project-\(index)",
                name: projectNames[index - 1],
                ownerName: "You",
                createdAt: baseDate.addingTimeInterval(TimeInterval(-index * 86_400)),
                updatedAt: baseDate.addingTimeInterval(TimeInterval(-index * 3_600)),
                description: "",
                sharedUserCount: 4,
                roomScans: makeRoomScans(projectIndex: index)
            )
        }
    }

    private nonisolated static let fixtureBaseDate = Date(timeIntervalSince1970: 1_750_000_000)

    /// Matches `AuthenticationSession.mockAppleUser` without crossing MainActor isolation.
    private nonisolated static let mockCurrentUserID = "mock-user-apple"
    private nonisolated static let mockCurrentUserDisplayName = "Mock Apple User"

    private nonisolated static let projectNames = [
        "Lakeside Remodel",
        "Downtown Loft",
        "Market Street Retail",
        "North Campus Suite",
        "Hillview Residence",
        "Atrium Office",
        "Garden Apartment",
        "Warehouse Conversion",
        "Harbor Guest House",
        "Pine Dental Clinic",
        "South Wing Lobby",
        "Cedar Workshop",
        "Ridgeview Kitchen",
        "Union Hall"
    ]

    private nonisolated static func makeRoomScans(projectIndex: Int) -> [RoomScanSummary] {
        let baseDate = fixtureBaseDate
        let roomNames = [
            "Living Room",
            "Kitchen",
            "Primary Bedroom",
            "Guest Bath",
            "Entry Hall",
            "Office",
            "Dining Room"
        ]
        let count = 2 + (projectIndex % 6)

        return (0..<count).map { index in
            let scanNumber = index + 1
            let scanID = "project-\(projectIndex)-scan-\(scanNumber)"
            let createdAt = baseDate.addingTimeInterval(
                TimeInterval(-(projectIndex * 86_400 + index * 3_600))
            )
            let thumbnailName = "thumbnail-\((projectIndex + index) % 5)"
            let syncStatusIndex = (projectIndex + index) % RoomScanSyncStatus.allCases.count
            let syncStatus = RoomScanSyncStatus.allCases[syncStatusIndex]
            let notes = makeNotes(projectIndex: projectIndex, scanIndex: scanNumber)

            let isCurrentUser = (projectIndex + index) % 5 != 0
            return RoomScanSummary(
                id: scanID,
                name: roomNames[index],
                createdAt: createdAt,
                localModelURL: mockModelURL(forProjectIndex: projectIndex),
                thumbnailName: thumbnailName,
                syncStatus: syncStatus,
                creatorUserID: isCurrentUser
                    ? mockCurrentUserID
                    : "other-user-\(projectIndex)",
                creatorDisplayName: isCurrentUser
                    ? mockCurrentUserDisplayName
                    : "Alex Rivera",
                notes: notes
            )
        }
    }

    private nonisolated static func mockModelURL(forProjectIndex projectIndex: Int) -> URL? {
        guard projectIndex <= 3 else { return nil }
        return DefaultModelLoadingService.mockSampleURL
    }

    private nonisolated static func makeNotes(projectIndex: Int, scanIndex: Int) -> [RoomScanNoteSummary] {
        let count = (projectIndex + scanIndex) % 3
        guard count > 0 else { return [] }

        let baseDate = fixtureBaseDate
        return (1...count).map { index in
            RoomScanNoteSummary(
                id: "project-\(projectIndex)-scan-\(scanIndex)-note-\(index)",
                text: "Note \(index)",
                createdAt: baseDate.addingTimeInterval(TimeInterval(-(projectIndex + scanIndex + index) * 600))
            )
        }
    }
}
