//
//  PendingAcceptedSharedIngestQueueTests.swift
//  roomscanTests
//

import Foundation
import Testing
@testable import roomscan

@MainActor
struct PendingAcceptedSharedIngestQueueTests {
    @Test func failedUpsertIsRetainedAndAppearsAfterSuccessfulRetry() async throws {
        let destination = AcceptedInvitationDestination.project(makeProject(id: "accepted-project"))
        let service = MockSharedService(
            scenario: .failLoad,
            projects: [],
            scans: [],
            simulatedDelayNanoseconds: 0
        )
        let queue = PendingAcceptedSharedIngestQueue(service: service)

        let firstAttempt = await queue.ingest(destination)
        #expect(firstAttempt == false)
        #expect(queue.pendingDestinations.map(\.id) == [destination.id])
        await #expect(throws: SharedServiceError.network) {
            try await service.fetchSharedProjects()
        }

        await service.setScenario(.success)
        await queue.retryPending()

        #expect(queue.pendingDestinations.isEmpty)
        let projects = try await service.fetchSharedProjects()
        #expect(projects.map(\.id) == ["accepted-project"])
    }

    @Test func failedScanUpsertIsRetainedUntilRetrySucceeds() async throws {
        let destination = AcceptedInvitationDestination.scan(makeSharedScan(id: "accepted-scan"))
        let service = MockSharedService(
            scenario: .failLoad,
            projects: [],
            scans: [],
            simulatedDelayNanoseconds: 0
        )
        let queue = PendingAcceptedSharedIngestQueue(service: service)

        let firstAttempt = await queue.ingest(destination)
        #expect(firstAttempt == false)
        #expect(queue.pendingDestinations.map(\.id) == [destination.id])

        await service.setScenario(.success)
        await queue.retryPending()

        #expect(queue.pendingDestinations.isEmpty)
        let scans = try await service.fetchSharedScans()
        #expect(scans.map(\.id) == ["accepted-scan"])
    }

    private func makeProject(id: String) -> ProjectSummary {
        ProjectSummary(
            id: id,
            name: "Accepted Project",
            ownerName: "Owner",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            description: "Shared via invitation",
            sharedUserCount: 1,
            roomScans: []
        )
    }

    private func makeSharedScan(id: String) -> SharedScanItem {
        SharedScanItem.make(
            from: RoomScanSummary(
                id: id,
                name: "Accepted Scan",
                createdAt: Date(timeIntervalSince1970: 1_500),
                localModelURL: nil,
                thumbnailName: "thumbnail",
                syncStatus: .synced,
                creatorUserID: "owner-1",
                creatorDisplayName: "Owner",
                notes: []
            ),
            parent: SharedScanParent(
                ownerName: "Owner",
                projectID: "shared-project",
                projectName: "Shared Project"
            ),
            status: .active,
            statusChangedAt: Date(timeIntervalSince1970: 1_500)
        )
    }
}
