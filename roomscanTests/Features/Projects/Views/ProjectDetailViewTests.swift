//
//  ProjectDetailViewTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

struct ProjectDetailViewTests {
    @Test func createdDateTextUsesAbbreviatedMonthDayAndYear() {
        let date = Date(timeIntervalSince1970: 1_750_000_000)

        #expect(
            ProjectDetailPresentation.createdDateText(
                for: date,
                locale: Locale(identifier: "en_US_POSIX")
            ) == "Jun 15, 2025"
        )
    }

    @Test func sharedUserCountTextDisplaysPeopleCount() {
        #expect(ProjectDetailPresentation.sharedUserCountText(for: 0) == "0 people")
        #expect(ProjectDetailPresentation.sharedUserCountText(for: 1) == "1 person")
        #expect(ProjectDetailPresentation.sharedUserCountText(for: 2) == "2 people")
    }

    @Test func scansTitleDisplaysCurrentScanCount() {
        #expect(ProjectDetailPresentation.scansTitle(for: 0) == "Scans (0)")
        #expect(ProjectDetailPresentation.scansTitle(for: 4) == "Scans (4)")
    }

    @Test func showsOwnerActionsOnlyForEditableAccessPolicy() {
        #expect(ProjectDetailPresentation.showsOwnerActions(for: .editable))
        #expect(ProjectDetailPresentation.showsOwnerActions(for: .readOnly) == false)
        #expect(DetailAccessPolicy.editable.allowsOwnerActions)
        #expect(DetailAccessPolicy.readOnly.allowsOwnerActions == false)
    }

    @Test func ownerNameUsesProjectOwnerAndUsesTheAccessPolicyForMissingValues() {
        #expect(
            ProjectDetailPresentation.ownerName("Project Owner", accessPolicy: .editable) == "Project Owner"
        )
        #expect(
            ProjectDetailPresentation.ownerName("owner@example.com", accessPolicy: .readOnly) == "owner@example.com"
        )
        #expect(
            ProjectDetailPresentation.ownerName("   ", accessPolicy: .editable) == "You"
        )
        #expect(
            ProjectDetailPresentation.ownerName("   ", accessPolicy: .readOnly)
                == String(localized: "shared.owner.unknown")
        )
    }

    @Test func canShareProjectRequiresAtLeastOneSyncedScan() {
        let pending = makeScan(id: "pending", syncStatus: .pending)
        let failed = makeScan(id: "failed", syncStatus: .failed)
        let synced = makeScan(id: "synced", syncStatus: .synced)

        #expect(
            ProjectDetailPresentation.canShareProject(
                localScans: [pending, failed],
                displayedScans: []
            ) == false
        )
        #expect(
            ProjectDetailPresentation.canShareProject(
                localScans: [pending, synced],
                displayedScans: []
            )
        )
        #expect(
            ProjectDetailPresentation.canShareProject(
                localScans: [],
                displayedScans: [synced]
            )
        )
        #expect(
            ProjectDetailPresentation.canShareProject(
                localScans: [pending],
                displayedScans: [synced]
            )
        )
        #expect(
            ProjectDetailPresentation.canShareProject(
                localScans: [],
                displayedScans: [pending]
            ) == false
        )
        #expect(
            ProjectDetailPresentation.canShareProject(
                localScans: [makeScan(id: "assets", syncStatus: .pending, assetStatus: "UPLOADED")],
                displayedScans: []
            )
        )
    }

    private func makeScan(
        id: String,
        syncStatus: RoomScanSyncStatus,
        assetStatus: String? = nil
    ) -> RoomScanSummary {
        RoomScanSummary(
            id: id,
            name: "Room",
            createdAt: Date(timeIntervalSince1970: 1_000),
            thumbnailName: "thumbnail-0",
            syncStatus: syncStatus,
            notes: [],
            assetStatus: assetStatus
        )
    }
}
