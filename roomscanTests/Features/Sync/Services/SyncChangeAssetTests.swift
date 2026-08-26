//
//  SyncChangeAssetTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

@MainActor
struct SyncChangeAssetTests {
    @Test func scanAssetUpsertUpdatesStatusAfterParentScanExists() async throws {
        let localStore = SyncTestFixtures.makeLocalStore()
        let applier = SyncChangeApplier(localCache: localStore, currentUserID: "user-1")
        let assetChange = SyncChange(
            resourceId: "asset-1",
            operation: .upsert,
            revision: 1,
            syncStatus: "SYNCED",
            changedAt: Date(),
            cursor: "c-asset",
            deletedAt: nil,
            resourceType: .scanAsset,
            payload: .scanAsset(
                SyncScanAssetPayload(
                    id: "asset-1",
                    scanId: "scan-1",
                    assetType: "MODEL",
                    status: "SYNCED",
                    contentType: "model/vnd.usdz+zip",
                    sizeBytes: 12,
                    checksum: "abc",
                    modelVersion: "1",
                    uploadedAt: Date(),
                    createdAt: Date(),
                    updatedAt: Date()
                )
            )
        )
        let scanChange = try SyncTestFixtures.makeScanChange(
            id: "scan-1",
            projectId: "project-1",
            name: "Kitchen",
            cursor: "c-scan"
        )

        try await applier.apply([
            assetChange,
            scanChange,
            SyncTestFixtures.makeProjectChange(id: "project-1", name: "Home")
        ])

        let project = try await localStore.fetchProject(id: "project-1")
        #expect(project.roomScans.first?.syncStatus == .synced)
    }

    @Test func scanAssetModelDeleteClearsMeshPathButKeepsLocalModelAndThumbnail() async throws {
        let localStore = SyncTestFixtures.makeLocalStore()
        let defaults = UserDefaults(suiteName: "SyncChangeAssetTests.\(UUID().uuidString)")!
        let applier = SyncChangeApplier(
            localCache: localStore,
            currentUserID: "user-1",
            defaults: defaults
        )
        try await localStore.cacheProject(SyncTestFixtures.makeKitchenScanProject())
        try await applier.apply([
            SyncChange(
                resourceId: "asset-1",
                operation: .upsert,
                revision: 1,
                syncStatus: "SYNCED",
                changedAt: Date(),
                cursor: "c-asset",
                deletedAt: nil,
                resourceType: .scanAsset,
                payload: .scanAsset(
                    SyncScanAssetPayload(
                        id: "asset-1",
                        scanId: "scan-1",
                        assetType: "MODEL",
                        status: "SYNCED",
                        contentType: nil,
                        sizeBytes: nil,
                        checksum: nil,
                        modelVersion: nil,
                        uploadedAt: nil,
                        createdAt: nil,
                        updatedAt: nil
                    )
                )
            )
        ])
        try await applier.apply([
            SyncChange(
                resourceId: "asset-1",
                operation: .delete,
                revision: 2,
                syncStatus: nil,
                changedAt: Date(),
                cursor: "c-del",
                deletedAt: Date(),
                resourceType: .scanAsset,
                payload: nil
            )
        ])

        let project = try await localStore.fetchProject(id: "project-1")
        #expect(project.roomScans.first?.meshPath.isEmpty == true)
        #expect(project.roomScans.first?.localModelURL == URL(fileURLWithPath: "/tmp/mesh.usdz"))
        #expect(project.roomScans.first?.thumbnailPath == "Scans/scan-1/thumbnail.jpg")
        #expect(project.roomScans.first?.hasLocalUploadArtifacts == true)
    }

    @Test func payloadLessScanAssetDeleteKeepsIndexUntilLocalScanExists() async throws {
        let localStore = SyncTestFixtures.makeLocalStore()
        let defaults = UserDefaults(suiteName: "SyncChangeAssetTests.\(UUID().uuidString)")!
        let applier = SyncChangeApplier(
            localCache: localStore,
            currentUserID: "user-1",
            defaults: defaults
        )
        let assetUpsert = SyncChange(
            resourceId: "asset-1",
            operation: .upsert,
            revision: 1,
            syncStatus: "SYNCED",
            changedAt: Date(),
            cursor: "c-asset",
            deletedAt: nil,
            resourceType: .scanAsset,
            payload: .scanAsset(
                SyncScanAssetPayload(
                    id: "asset-1",
                    scanId: "scan-1",
                    assetType: "MODEL",
                    status: "SYNCED",
                    contentType: nil,
                    sizeBytes: nil,
                    checksum: nil,
                    modelVersion: nil,
                    uploadedAt: nil,
                    createdAt: nil,
                    updatedAt: nil
                )
            )
        )
        let payloadLessDelete = SyncChange(
            resourceId: "asset-1",
            operation: .delete,
            revision: 2,
            syncStatus: nil,
            changedAt: Date(),
            cursor: "c-del",
            deletedAt: Date(),
            resourceType: .scanAsset,
            payload: nil
        )

        try await applier.apply([assetUpsert, payloadLessDelete])
        try await localStore.cacheProject(SyncTestFixtures.makeKitchenScanProject())
        try await applier.apply([payloadLessDelete])

        let project = try await localStore.fetchProject(id: "project-1")
        #expect(project.roomScans.first?.meshPath.isEmpty == true)
        #expect(project.roomScans.first?.thumbnailPath == "Scans/scan-1/thumbnail.jpg")
    }

    @Test func scanAssetDeleteOfReplacedThumbnailKeepsCurrentPath() async throws {
        let localStore = SyncTestFixtures.makeLocalStore()
        let defaults = UserDefaults(suiteName: "SyncChangeAssetTests.\(UUID().uuidString)")!
        let applier = SyncChangeApplier(
            localCache: localStore,
            currentUserID: "user-1",
            defaults: defaults
        )
        try await localStore.cacheProject(SyncTestFixtures.makeKitchenScanProject())

        try await applier.apply([
            makeThumbnailAssetChange(id: "asset-old", revision: 1, cursor: "c-old")
        ])
        try await applier.apply([
            makeThumbnailAssetChange(id: "asset-new", revision: 2, cursor: "c-new")
        ])
        try await applier.apply([
            SyncChange(
                resourceId: "asset-old",
                operation: .delete,
                revision: 3,
                syncStatus: nil,
                changedAt: Date(),
                cursor: "c-del-old",
                deletedAt: Date(),
                resourceType: .scanAsset,
                payload: nil
            )
        ])

        let project = try await localStore.fetchProject(id: "project-1")
        #expect(project.roomScans.first?.thumbnailPath == "Scans/scan-1/thumbnail.jpg")
        #expect(project.roomScans.first?.meshPath == "Scans/scan-1/mesh.usdz")
    }

    private func makeThumbnailAssetChange(id: String, revision: Int, cursor: String) -> SyncChange {
        SyncChange(
            resourceId: id,
            operation: .upsert,
            revision: revision,
            syncStatus: "SYNCED",
            changedAt: Date(),
            cursor: cursor,
            deletedAt: nil,
            resourceType: .scanAsset,
            payload: .scanAsset(
                SyncScanAssetPayload(
                    id: id,
                    scanId: "scan-1",
                    assetType: "THUMBNAIL",
                    status: "SYNCED",
                    contentType: nil,
                    sizeBytes: nil,
                    checksum: nil,
                    modelVersion: nil,
                    uploadedAt: nil,
                    createdAt: nil,
                    updatedAt: nil
                )
            )
        )
    }
}
