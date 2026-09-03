//
//  ProjectSummaryScanCountTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

struct ProjectSummaryScanCountTests {
    @Test func withRoomScansPreservesRemoteTotalWhenLocalCacheIsIncomplete() {
        let project = makeProject(remoteScanCount: 5, localScans: [makeScan(id: "local-1")])

        let renamed = project.withRoomScans([
            makeScan(id: "local-1", name: "Renamed")
        ])

        #expect(renamed.roomScans.count == 1)
        #expect(renamed.scanCount == 5)
        #expect(renamed.scansContentState == .local)
    }

    @Test func replacingScanPreservesRemoteTotal() {
        let project = makeProject(remoteScanCount: 4, localScans: [makeScan(id: "local-1")])
        let updated = project.replacingScan(makeScan(id: "local-1", name: "Kitchen"))

        #expect(updated?.scanCount == 4)
        #expect(updated?.roomScans.first?.name == "Kitchen")
    }

    @Test func removingScanAppliesDeltaAndKeepsRemoteRemainder() {
        let project = makeProject(remoteScanCount: 3, localScans: [makeScan(id: "local-1")])
        let updated = project.removingScan(id: "local-1")

        #expect(updated.roomScans.isEmpty)
        #expect(updated.scanCount == 2)
        #expect(updated.scansContentState == .remoteOnly)
    }

    @Test func removingScan_whenMissing_doesNotDecrementCount() {
        let project = makeProject(remoteScanCount: 3, localScans: [makeScan(id: "local-1")])
        let updated = project.removingScan(id: "missing")

        #expect(updated == project)
        #expect(updated.scanCount == 3)
        #expect(updated.roomScans.count == 1)
    }

    @Test func addingLocalScanIncrementsRemoteTotal() {
        let project = makeProject(remoteScanCount: 3, localScans: [makeScan(id: "local-1")])
        let updated = project.withRoomScans(
            [makeScan(id: "local-2"), makeScan(id: "local-1")],
            scanCountDelta: 1
        )

        #expect(updated.roomScans.count == 2)
        #expect(updated.scanCount == 4)
    }

    @Test func mergingRemoteCache_allowsRemoteScanCountToDecrease() {
        let existing = makeProject(
            remoteScanCount: 5,
            localScans: [makeScan(id: "scan-1")]
        )
        let incoming = ProjectSummary(
            id: "project-1",
            name: "Incomplete Local Cache",
            roomScans: [makeScan(id: "scan-1")],
            scanCount: 2
        )

        let merged = ProjectSummary.mergingRemoteCache(incoming, over: existing)

        #expect(merged.roomScans.count == 1)
        #expect(merged.scanCount == 2)
    }

    @Test func mergingRemoteCache_clampsToLocalOnlyScans() {
        let existing = makeProject(
            remoteScanCount: 5,
            localScans: [makeScan(id: "pending-local")]
        )
        let incoming = ProjectSummary(
            id: "project-1",
            name: "Incomplete Local Cache",
            roomScans: [],
            scanCount: 0
        )

        let merged = ProjectSummary.mergingRemoteCache(incoming, over: existing)

        #expect(merged.roomScans.count == 1)
        #expect(merged.roomScans.first?.id == "pending-local")
        #expect(merged.scanCount == 1)
    }

    @Test @MainActor
    func localServiceRenamePreservesRemoteScanCountAboveLocalCache() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectSummaryScanCount_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let service = LocalProjectsService(directory: tempDir, seedIfEmpty: false)
        try await service.cacheProject(
            makeProject(remoteScanCount: 5, localScans: [makeScan(id: "scan-1")])
        )

        _ = try await service.renameScan(projectID: "project-1", scanID: "scan-1", name: "Renamed")

        let renamed = try await service.fetchProject(id: "project-1")
        #expect(renamed.scanCount == 5)
        #expect(renamed.roomScans.count == 1)

        try await service.deleteScan(projectID: "project-1", scanID: "scan-1")
        let afterDelete = try await service.fetchProject(id: "project-1")
        #expect(afterDelete.roomScans.isEmpty)
        #expect(afterDelete.scanCount == 4)
        #expect(afterDelete.scansContentState == .remoteOnly)
    }

    @Test func hasUploadedScanIsTrueWhenAnyScanIsSynced() {
        let project = makeProject(
            remoteScanCount: 2,
            localScans: [
                makeScan(id: "pending", syncStatus: .pending),
                makeScan(id: "uploaded", syncStatus: .synced)
            ]
        )

        #expect(project.hasUploadedScan)
    }

    @Test func hasUploadedScanIsTrueWhenPendingScanHasUploadedAssets() {
        let project = makeProject(
            remoteScanCount: 1,
            localScans: [
                makeScan(id: "uploaded", syncStatus: .pending, assetStatus: "UPLOADED")
            ]
        )

        #expect(project.hasUploadedScan)
    }

    @Test func hasUploadedScanIsFalseWhenEveryScanIsPendingOrFailed() {
        let project = makeProject(
            remoteScanCount: 2,
            localScans: [
                makeScan(id: "pending", syncStatus: .pending),
                makeScan(id: "failed", syncStatus: .failed)
            ]
        )

        #expect(!project.hasUploadedScan)
    }

    @Test func hasUploadedScanIsFalseWhenThereAreNoScans() {
        let project = makeProject(remoteScanCount: 0, localScans: [])

        #expect(!project.hasUploadedScan)
    }

    private func makeProject(
        remoteScanCount: Int,
        localScans: [RoomScanSummary]
    ) -> ProjectSummary {
        ProjectSummary(
            id: "project-1",
            name: "Incomplete Local Cache",
            roomScans: localScans,
            scanCount: remoteScanCount
        )
    }

    private func makeScan(
        id: String,
        name: String = "Room",
        syncStatus: RoomScanSyncStatus = .synced,
        assetStatus: String? = nil
    ) -> RoomScanSummary {
        RoomScanSummary(
            id: id,
            name: name,
            createdAt: Date(timeIntervalSince1970: 1_000),
            thumbnailName: "thumbnail-0",
            syncStatus: syncStatus,
            notes: [],
            assetStatus: assetStatus
        )
    }
}
