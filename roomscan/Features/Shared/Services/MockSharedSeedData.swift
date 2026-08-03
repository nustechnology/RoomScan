//
//  MockSharedSeedData.swift
//  roomscan
//

import Foundation

enum MockSharedSeedData {
    private nonisolated static let fixtureBaseDate = Date(timeIntervalSince1970: 1_750_000_000)

    nonisolated static func makeSeedProjects(now: Date = Date()) -> [SharedProjectItem] {
        makeActiveProjects() + makeInactiveProjects(now: now)
    }

    nonisolated static func makeSeedScans(now: Date = Date()) -> [SharedScanItem] {
        makeActiveScans() + makeInactiveScans(now: now)
    }

    private nonisolated static func makeActiveProjects() -> [SharedProjectItem] {
        let projects: [ProjectSummary] = [
            .init(
                id: "shared-project-active",
                name: "Company Office — Floor 3",
                ownerName: "Nguyen Minh Anh",
                createdAt: fixtureBaseDate.addingTimeInterval(-30 * 86_400),
                updatedAt: fixtureBaseDate.addingTimeInterval(-2 * 86_400),
                description: "Shared office floor plan for collaboration.",
                sharedUserCount: 3,
                roomScans: detailScans(projectID: "shared-project-active", count: 4)
            ),
            .init(
                id: "shared-project-active-2",
                name: "Harbor Guest House",
                ownerName: "Jordan Lee",
                createdAt: fixtureBaseDate.addingTimeInterval(-14 * 86_400),
                updatedAt: fixtureBaseDate.addingTimeInterval(-1 * 86_400),
                description: "",
                sharedUserCount: 1,
                roomScans: detailScans(projectID: "shared-project-active-2", count: 3)
            ),
            .init(
                id: "shared-project-empty-scans",
                name: "New Shared Shell",
                ownerName: "Chris Phan",
                createdAt: fixtureBaseDate.addingTimeInterval(-2 * 86_400),
                updatedAt: fixtureBaseDate.addingTimeInterval(-2 * 86_400),
                description: "Shared project that has no scans yet.",
                sharedUserCount: 1,
                roomScans: []
            )
        ]
        return projects.map {
            SharedProjectItem.make(from: $0, status: .active, statusChangedAt: fixtureBaseDate)
        }
    }

    private nonisolated static func makeInactiveProjects(now: Date) -> [SharedProjectItem] {
        let revokedScans = detailScans(projectID: "shared-project-revoked", count: 2)
        return [
            SharedProjectItem(
                id: "shared-project-revoked",
                name: "District 2 Apartment",
                ownerName: "Tran Thi Mai",
                scanCount: revokedScans.count,
                thumbnailName: SharedProjectItem.thumbnailName(from: revokedScans),
                status: .accessRevoked,
                statusChangedAt: now.addingTimeInterval(-2 * 86_400),
                detailProject: nil
            ),
            SharedProjectItem(
                id: "shared-project-deleted",
                name: "Binh Duong Warehouse",
                ownerName: "Dang Quoc Huy",
                scanCount: 5,
                thumbnailName: nil,
                status: .itemDeleted,
                statusChangedAt: now.addingTimeInterval(-3 * 86_400),
                detailProject: nil
            ),
            SharedProjectItem(
                id: "shared-project-expired",
                name: "Old Shared Studio",
                ownerName: "Alex Rivera",
                scanCount: 1,
                thumbnailName: nil,
                status: .accessRevoked,
                statusChangedAt: now.addingTimeInterval(-10 * 86_400),
                detailProject: nil
            )
        ]
    }

    private nonisolated static func makeActiveScans() -> [SharedScanItem] {
        let meeting = scanSummary(id: "shared-scan-active", name: "Meeting Room 3A", daysAgo: 5, noteCount: 4, hasModel: true)
        let bedroom = scanSummary(id: "shared-scan-active-2", name: "Primary Bedroom", daysAgo: 3, noteCount: 1, hasModel: false)

        return [
            SharedScanItem(
                id: meeting.id,
                name: meeting.name,
                ownerName: "Dang Quoc Huy",
                noteCount: meeting.notes.count,
                projectID: "shared-project-active",
                projectName: "Binh Duong Warehouse",
                thumbnailName: "ScanThumbnail",
                status: .active,
                statusChangedAt: fixtureBaseDate,
                detailScan: meeting
            ),
            SharedScanItem(
                id: bedroom.id,
                name: bedroom.name,
                ownerName: "Jordan Lee",
                noteCount: bedroom.notes.count,
                projectID: "shared-project-active-2",
                projectName: "Harbor Guest House",
                thumbnailName: "ScanThumbnail",
                status: .active,
                statusChangedAt: fixtureBaseDate,
                detailScan: bedroom
            )
        ]
    }

    private nonisolated static func makeInactiveScans(now: Date) -> [SharedScanItem] {
        [
            SharedScanItem(
                id: "shared-scan-revoked",
                name: "Living Room",
                ownerName: "Nguyen Minh Anh",
                noteCount: 2,
                projectID: "shared-project-revoked",
                projectName: "District 2 Apartment",
                thumbnailName: "ScanThumbnail",
                status: .accessRevoked,
                statusChangedAt: now.addingTimeInterval(-1 * 86_400),
                detailScan: nil
            ),
            SharedScanItem(
                id: "shared-scan-deleted",
                name: "Kitchen",
                ownerName: "Tran Thi Mai",
                noteCount: 0,
                projectID: "shared-project-deleted",
                projectName: "Company Office — Floor 3 With A Very Long Project Name",
                thumbnailName: nil,
                status: .itemDeleted,
                statusChangedAt: now.addingTimeInterval(-4 * 86_400),
                detailScan: nil
            ),
            SharedScanItem(
                id: "shared-scan-expired",
                name: "Expired Lobby",
                ownerName: "Alex Rivera",
                noteCount: 1,
                projectID: "shared-project-expired",
                projectName: "Old Shared Studio",
                thumbnailName: nil,
                status: .itemDeleted,
                statusChangedAt: now.addingTimeInterval(-9 * 86_400),
                detailScan: nil
            )
        ]
    }

    private nonisolated static func scanSummary(
        id: String,
        name: String,
        daysAgo: Int,
        noteCount: Int,
        hasModel: Bool
    ) -> RoomScanSummary {
        let notes = (0..<noteCount).map { index in
            RoomScanNoteSummary(
                id: "\(id)-note-\(index + 1)",
                text: "Note \(index + 1)",
                createdAt: fixtureBaseDate
            )
        }
        return RoomScanSummary(
            id: id,
            name: name,
            createdAt: fixtureBaseDate.addingTimeInterval(TimeInterval(-daysAgo * 86_400)),
            localModelURL: hasModel ? URL(string: "roomscan-sample://viewer/sample-room") : nil,
            thumbnailName: "ScanThumbnail",
            syncStatus: .synced,
            creatorUserID: "shared-owner",
            creatorDisplayName: "Shared Owner",
            notes: notes
        )
    }

    private nonisolated static func detailScans(projectID: String, count: Int) -> [RoomScanSummary] {
        let names = ["Living Room", "Kitchen", "Meeting Room 3A", "Office", "Entry Hall"]
        return (0..<count).map { index in
            RoomScanSummary(
                id: "\(projectID)-scan-\(index + 1)",
                name: names[index % names.count],
                createdAt: fixtureBaseDate.addingTimeInterval(TimeInterval(-(index + 1) * 86_400)),
                localModelURL: index == 0 ? URL(string: "roomscan-sample://viewer/sample-room") : nil,
                thumbnailName: index == 0 ? "ScanThumbnail" : "missing-thumbnail-\(index)",
                syncStatus: .synced,
                creatorUserID: "shared-owner",
                creatorDisplayName: "Shared Owner",
                notes: []
            )
        }
    }
}
