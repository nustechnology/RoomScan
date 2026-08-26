//
//  SyncChangeApplierTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

@MainActor
struct SyncChangeApplierTests {
    @Test func applySortsParentsBeforeChildrenSoNotesAreNotDropped() async throws {
        let localStore = SyncTestFixtures.makeLocalStore()
        let applier = SyncChangeApplier(localCache: localStore, currentUserID: "user-1")
        let noteChange = SyncChange(
            resourceId: "note-1",
            operation: .upsert,
            revision: 1,
            syncStatus: nil,
            changedAt: Date(),
            cursor: "c-note",
            deletedAt: nil,
            resourceType: .note,
            payload: .note(
                SyncNotePayload(
                    id: "note-1",
                    scanId: "scan-1",
                    createdById: "user-1",
                    creatorEmail: nil,
                    title: "Title",
                    content: "Body",
                    color: nil,
                    createdAt: Date(timeIntervalSince1970: 300),
                    updatedAt: nil
                )
            )
        )
        let scanChange = SyncChange(
            resourceId: "scan-1",
            operation: .upsert,
            revision: 1,
            syncStatus: "PENDING",
            changedAt: Date(),
            cursor: "c-scan",
            deletedAt: nil,
            resourceType: .scan,
            payload: .scan(
                try SyncTestFixtures.decodeScanPayload(
                    """
                    {
                      "id": "scan-1",
                      "projectId": "project-1",
                      "name": "Kitchen",
                      "createdAt": "2026-01-01T00:00:00.000Z",
                      "syncStatus": "PENDING"
                    }
                    """
                )
            )
        )

        try await applier.apply([noteChange, scanChange, SyncTestFixtures.makeProjectChange(id: "project-1", name: "Home")])

        let project = try await localStore.fetchProject(id: "project-1")
        #expect(project.roomScans.first?.id == "scan-1")
        #expect(project.roomScans.first?.notes.contains(where: { $0.id == "note-1" }) == true)
    }

    @Test func sortedForApplyPreservesDeleteBeforeUpsertAcrossOperationBoundary() {
        let deleteAccess = SyncChange(
            resourceId: "access-1",
            operation: .delete,
            revision: 1,
            syncStatus: nil,
            changedAt: Date(timeIntervalSince1970: 1),
            cursor: "c-del",
            deletedAt: Date(timeIntervalSince1970: 1),
            resourceType: .projectAccess,
            payload: nil
        )
        let upsertAccess = SyncChange(
            resourceId: "access-2",
            operation: .upsert,
            revision: 2,
            syncStatus: nil,
            changedAt: Date(timeIntervalSince1970: 2),
            cursor: "c-up",
            deletedAt: nil,
            resourceType: .projectAccess,
            payload: .projectAccess(
                SyncProjectAccessPayload(
                    id: "access-2",
                    projectId: "shared-project",
                    userId: "user-1",
                    userEmail: "me@example.com",
                    role: "EDITOR",
                    acceptedAt: Date(timeIntervalSince1970: 2),
                    createdAt: Date(timeIntervalSince1970: 2),
                    updatedAt: Date(timeIntervalSince1970: 2)
                )
            )
        )
        let deleteAsset = SyncChange(
            resourceId: "asset-old",
            operation: .delete,
            revision: 3,
            syncStatus: nil,
            changedAt: Date(timeIntervalSince1970: 3),
            cursor: "c-asset-del",
            deletedAt: Date(timeIntervalSince1970: 3),
            resourceType: .scanAsset,
            payload: nil
        )
        let upsertAsset = SyncChange(
            resourceId: "asset-new",
            operation: .upsert,
            revision: 4,
            syncStatus: "SYNCED",
            changedAt: Date(timeIntervalSince1970: 4),
            cursor: "c-asset-up",
            deletedAt: nil,
            resourceType: .scanAsset,
            payload: .scanAsset(
                SyncScanAssetPayload(
                    id: "asset-new",
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

        let sorted = SyncChangeApplier.sortedForApply([
            deleteAccess, upsertAccess, deleteAsset, upsertAsset
        ])

        #expect(sorted.map(\.resourceId) == [
            "access-1", "access-2", "asset-old", "asset-new"
        ])
    }

    @Test func sortedForApplyRanksWithinContiguousOperationRunsOnly() {
        let noteUpsert = SyncTestFixtures.makeNoteChange(id: "note-1", scanId: "scan-1")
        let projectUpsert = SyncTestFixtures.makeProjectChange(id: "project-1", name: "Home")
        let projectDelete = SyncChange(
            resourceId: "project-old",
            operation: .delete,
            revision: 1,
            syncStatus: nil,
            changedAt: Date(timeIntervalSince1970: 1),
            cursor: "c-del-project",
            deletedAt: Date(timeIntervalSince1970: 1),
            resourceType: .project,
            payload: nil
        )
        let noteDelete = SyncChange(
            resourceId: "note-old",
            operation: .delete,
            revision: 1,
            syncStatus: nil,
            changedAt: Date(timeIntervalSince1970: 1),
            cursor: "c-del-note",
            deletedAt: Date(timeIntervalSince1970: 1),
            resourceType: .note,
            payload: nil
        )

        let sorted = SyncChangeApplier.sortedForApply([
            noteUpsert, projectUpsert, projectDelete, noteDelete
        ])

        #expect(sorted.map(\.resourceId) == [
            "project-1", "note-1", "note-old", "project-old"
        ])
    }

    @Test func projectAccessDeleteThenReaddInSameBatchEndsActive() async throws {
        let localStore = SyncTestFixtures.makeLocalStore()
        let sharedService = MockSharedService(projects: [], scans: [], simulatedDelayNanoseconds: 0)
        let defaults = UserDefaults(suiteName: "SyncEngineTests.\(UUID().uuidString)")!
        let applier = SyncChangeApplier(
            localCache: localStore,
            sharedService: sharedService,
            currentUserID: "user-1",
            defaults: defaults
        )
        try await localStore.cacheProject(
            ProjectSummary(
                id: "shared-project",
                name: "Shared Villa",
                ownerName: "owner@example.com",
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 2),
                description: "",
                sharedUserCount: 1,
                roomScans: []
            )
        )

        try await applier.apply([
            SyncChange(
                resourceId: "access-1",
                operation: .upsert,
                revision: 1,
                syncStatus: nil,
                changedAt: Date(timeIntervalSince1970: 1),
                cursor: "c-access-1",
                deletedAt: nil,
                resourceType: .projectAccess,
                payload: .projectAccess(
                    SyncProjectAccessPayload(
                        id: "access-1",
                        projectId: "shared-project",
                        userId: "user-1",
                        userEmail: "me@example.com",
                        role: "EDITOR",
                        acceptedAt: Date(timeIntervalSince1970: 1),
                        createdAt: Date(timeIntervalSince1970: 1),
                        updatedAt: Date(timeIntervalSince1970: 1)
                    )
                )
            )
        ])

        try await applier.apply([
            SyncChange(
                resourceId: "access-1",
                operation: .delete,
                revision: 2,
                syncStatus: nil,
                changedAt: Date(timeIntervalSince1970: 2),
                cursor: "c-del",
                deletedAt: Date(timeIntervalSince1970: 2),
                resourceType: .projectAccess,
                payload: nil
            ),
            SyncChange(
                resourceId: "access-2",
                operation: .upsert,
                revision: 3,
                syncStatus: nil,
                changedAt: Date(timeIntervalSince1970: 3),
                cursor: "c-access-2",
                deletedAt: nil,
                resourceType: .projectAccess,
                payload: .projectAccess(
                    SyncProjectAccessPayload(
                        id: "access-2",
                        projectId: "shared-project",
                        userId: "user-1",
                        userEmail: "me@example.com",
                        role: "EDITOR",
                        acceptedAt: Date(timeIntervalSince1970: 3),
                        createdAt: Date(timeIntervalSince1970: 3),
                        updatedAt: Date(timeIntervalSince1970: 3)
                    )
                )
            )
        ])

        let shared = try await sharedService.fetchSharedProjects()
        let item = shared.first(where: { $0.id == "shared-project" })
        #expect(item?.status == .active)
        #expect(item?.detailProject != nil)
    }

    @Test func projectAccessUpsertIngestsSharedProjectForCurrentUser() async throws {
        let localStore = SyncTestFixtures.makeLocalStore()
        let sharedService = MockSharedService(projects: [], scans: [], simulatedDelayNanoseconds: 0)
        let defaults = UserDefaults(suiteName: "SyncEngineTests.\(UUID().uuidString)")!
        let applier = SyncChangeApplier(
            localCache: localStore,
            sharedService: sharedService,
            currentUserID: "user-1",
            defaults: defaults
        )
        try await localStore.cacheProject(
            ProjectSummary(
                id: "shared-project",
                name: "Shared Villa",
                ownerName: "owner@example.com",
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 2),
                description: "",
                sharedUserCount: 1,
                roomScans: []
            )
        )

        try await applier.apply([
            SyncChange(
                resourceId: "access-1",
                operation: .upsert,
                revision: 1,
                syncStatus: nil,
                changedAt: Date(),
                cursor: "c-access",
                deletedAt: nil,
                resourceType: .projectAccess,
                payload: .projectAccess(
                    SyncProjectAccessPayload(
                        id: "access-1",
                        projectId: "shared-project",
                        userId: "user-1",
                        userEmail: "me@example.com",
                        role: "EDITOR",
                        acceptedAt: Date(timeIntervalSince1970: 3),
                        createdAt: Date(timeIntervalSince1970: 3),
                        updatedAt: Date(timeIntervalSince1970: 3)
                    )
                )
            )
        ])

        let shared = try await sharedService.fetchSharedProjects()
        #expect(shared.contains(where: { $0.id == "shared-project" && $0.status == .active }))
    }

    @Test func projectAccessOwnerDeleteWithPayloadDoesNotIngestShared() async throws {
        let localStore = SyncTestFixtures.makeLocalStore()
        let sharedService = MockSharedService(projects: [], scans: [], simulatedDelayNanoseconds: 0)
        let defaults = UserDefaults(suiteName: "SyncEngineTests.\(UUID().uuidString)")!
        let applier = SyncChangeApplier(
            localCache: localStore,
            sharedService: sharedService,
            currentUserID: "user-1",
            defaults: defaults
        )
        try await localStore.cacheProject(
            ProjectSummary(
                id: "owned-project",
                name: "My House",
                ownerName: "me@example.com",
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 2),
                description: "",
                sharedUserCount: 0,
                roomScans: []
            )
        )

        try await applier.apply([
            SyncChange(
                resourceId: "access-owner",
                operation: .upsert,
                revision: 1,
                syncStatus: nil,
                changedAt: Date(),
                cursor: "c-owner",
                deletedAt: nil,
                resourceType: .projectAccess,
                payload: .projectAccess(
                    SyncProjectAccessPayload(
                        id: "access-owner",
                        projectId: "owned-project",
                        userId: "user-1",
                        userEmail: "me@example.com",
                        role: "OWNER",
                        acceptedAt: Date(),
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                )
            )
        ])
        try await applier.apply([
            SyncChange(
                resourceId: "access-owner",
                operation: .delete,
                revision: 2,
                syncStatus: nil,
                changedAt: Date(),
                cursor: "c-del",
                deletedAt: Date(),
                resourceType: .projectAccess,
                payload: .projectAccess(
                    SyncProjectAccessPayload(
                        id: "access-owner",
                        projectId: "owned-project",
                        userId: "user-1",
                        userEmail: "me@example.com",
                        role: "OWNER",
                        acceptedAt: nil,
                        createdAt: nil,
                        updatedAt: nil
                    )
                )
            )
        ])

        let shared = try await sharedService.fetchSharedProjects()
        #expect(shared.contains(where: { $0.id == "owned-project" }) == false)
    }

    @Test func projectAccessOwnerDeleteWithoutPayloadDoesNotIngestShared() async throws {
        let localStore = SyncTestFixtures.makeLocalStore()
        let sharedService = MockSharedService(projects: [], scans: [], simulatedDelayNanoseconds: 0)
        let defaults = UserDefaults(suiteName: "SyncEngineTests.\(UUID().uuidString)")!
        let applier = SyncChangeApplier(
            localCache: localStore,
            sharedService: sharedService,
            currentUserID: "user-1",
            defaults: defaults
        )
        try await localStore.cacheProject(
            ProjectSummary(
                id: "owned-project",
                name: "My House",
                ownerName: "me@example.com",
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 2),
                description: "",
                sharedUserCount: 0,
                roomScans: []
            )
        )

        try await applier.apply([
            SyncChange(
                resourceId: "access-owner",
                operation: .upsert,
                revision: 1,
                syncStatus: nil,
                changedAt: Date(),
                cursor: "c-owner",
                deletedAt: nil,
                resourceType: .projectAccess,
                payload: .projectAccess(
                    SyncProjectAccessPayload(
                        id: "access-owner",
                        projectId: "owned-project",
                        userId: "user-1",
                        userEmail: "me@example.com",
                        role: "OWNER",
                        acceptedAt: Date(),
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                )
            )
        ])
        try await applier.apply([
            SyncChange(
                resourceId: "access-owner",
                operation: .delete,
                revision: 2,
                syncStatus: nil,
                changedAt: Date(),
                cursor: "c-del",
                deletedAt: Date(),
                resourceType: .projectAccess,
                payload: nil
            )
        ])

        let shared = try await sharedService.fetchSharedProjects()
        #expect(shared.contains(where: { $0.id == "owned-project" }) == false)
    }
    @Test func projectAccessDeleteWithoutPayloadUsesRememberedProjectId() async throws {
        let localStore = SyncTestFixtures.makeLocalStore()
        let sharedService = MockSharedService(projects: [], scans: [], simulatedDelayNanoseconds: 0)
        let defaults = UserDefaults(suiteName: "SyncEngineTests.\(UUID().uuidString)")!
        let applier = SyncChangeApplier(
            localCache: localStore,
            sharedService: sharedService,
            currentUserID: "user-1",
            defaults: defaults
        )

        try await applier.apply([
            SyncChange(
                resourceId: "access-1",
                operation: .upsert,
                revision: 1,
                syncStatus: nil,
                changedAt: Date(),
                cursor: "c-access",
                deletedAt: nil,
                resourceType: .projectAccess,
                payload: .projectAccess(
                    SyncProjectAccessPayload(
                        id: "access-1",
                        projectId: "shared-project",
                        userId: "user-1",
                        userEmail: "me@example.com",
                        role: "EDITOR",
                        acceptedAt: Date(),
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                )
            )
        ])
        try await applier.apply([
            SyncChange(
                resourceId: "access-1",
                operation: .delete,
                revision: 2,
                syncStatus: nil,
                changedAt: Date(),
                cursor: "c-del",
                deletedAt: Date(),
                resourceType: .projectAccess,
                payload: nil
            )
        ])

        let shared = try await sharedService.fetchSharedProjects()
        #expect(shared.contains(where: { $0.id == "shared-project" && $0.status == .accessRevoked }))
    }

    @Test func projectAccessDeleteWithoutPayloadRetriesAfterIngestFailure() async throws {
        let localStore = SyncTestFixtures.makeLocalStore()
        let sharedService = MockSharedService(projects: [], scans: [], simulatedDelayNanoseconds: 0)
        let defaults = UserDefaults(suiteName: "SyncEngineTests.\(UUID().uuidString)")!
        let applier = SyncChangeApplier(
            localCache: localStore,
            sharedService: sharedService,
            currentUserID: "user-1",
            defaults: defaults
        )

        try await applier.apply([
            SyncChange(
                resourceId: "access-1",
                operation: .upsert,
                revision: 1,
                syncStatus: nil,
                changedAt: Date(),
                cursor: "c-access",
                deletedAt: nil,
                resourceType: .projectAccess,
                payload: .projectAccess(
                    SyncProjectAccessPayload(
                        id: "access-1",
                        projectId: "shared-project",
                        userId: "user-1",
                        userEmail: "me@example.com",
                        role: "EDITOR",
                        acceptedAt: Date(),
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                )
            )
        ])
        await sharedService.setScenario(.failLoad)
        let deleteChange = SyncChange(
            resourceId: "access-1",
            operation: .delete,
            revision: 2,
            syncStatus: nil,
            changedAt: Date(),
            cursor: "c-del",
            deletedAt: Date(),
            resourceType: .projectAccess,
            payload: nil
        )
        await #expect(throws: SyncApplyError.persistFailed) {
            try await applier.apply([deleteChange])
        }

        await sharedService.setScenario(.success)
        let sharedAfterFailure = try await sharedService.fetchSharedProjects()
        #expect(sharedAfterFailure.contains(where: { $0.id == "shared-project" && $0.status == .active }))

        try await applier.apply([deleteChange])
        let shared = try await sharedService.fetchSharedProjects()
        #expect(shared.contains(where: { $0.id == "shared-project" && $0.status == .accessRevoked }))
    }

    @Test func upsertWithoutPayloadDoesNotUpdateRevision() async throws {
        let defaults = UserDefaults(suiteName: "SyncEngineTests.\(UUID().uuidString)")!
        let revisionStore = APIRevisionStore(defaults: defaults)
        let applier = SyncChangeApplier(
            localCache: SyncTestFixtures.makeLocalStore(),
            revisionStore: revisionStore,
            currentUserID: "user-1",
            defaults: defaults
        )

        try await applier.apply([
            SyncChange(
                resourceId: "project-1",
                operation: .upsert,
                revision: 9,
                syncStatus: nil,
                changedAt: Date(),
                cursor: "c1",
                deletedAt: nil,
                resourceType: .project,
                payload: nil
            )
        ])
        #expect(await revisionStore.currentRevision(for: "project-1") == APIRevision.initial)
    }

    @Test func projectUpsertWithUnknownRevisionAppliesOverHigherLocalRevision() async throws {
        let localStore = SyncTestFixtures.makeLocalStore()
        let defaults = UserDefaults(suiteName: "SyncEngineTests.\(UUID().uuidString)")!
        let revisionStore = APIRevisionStore(defaults: defaults)
        await revisionStore.update("4", for: "project-1")
        let applier = SyncChangeApplier(
            localCache: localStore,
            revisionStore: revisionStore,
            currentUserID: "user-1",
            defaults: defaults
        )
        try await localStore.cacheProject(
            ProjectSummary(
                id: "project-1",
                revision: 4,
                name: "Old Name",
                ownerName: "owner@example.com",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 200),
                description: "",
                sharedUserCount: 0,
                roomScans: []
            )
        )

        try await applier.apply([
            SyncChange(
                resourceId: "project-1",
                operation: .upsert,
                revision: nil,
                syncStatus: "SYNCED",
                changedAt: Date(timeIntervalSince1970: 300),
                cursor: "c-rename",
                deletedAt: nil,
                resourceType: .project,
                payload: .project(
                    SyncProjectPayload(
                        id: "project-1",
                        ownerId: "user-1",
                        ownerEmail: "owner@example.com",
                        name: "Renamed Elsewhere",
                        description: nil,
                        createdAt: Date(timeIntervalSince1970: 100),
                        updatedAt: Date(timeIntervalSince1970: 300),
                        lastSyncedAt: nil
                    )
                )
            )
        ])

        let project = try await localStore.fetchProject(id: "project-1")
        #expect(project.name == "Renamed Elsewhere")
        #expect(project.revision == 4)
        #expect(await revisionStore.currentRevision(for: "project-1") == "4")
    }

    @Test func projectUpsertWithLowerRevisionIsIgnored() async throws {
        let localStore = SyncTestFixtures.makeLocalStore()
        let applier = SyncChangeApplier(
            localCache: localStore,
            currentUserID: "user-1"
        )
        try await localStore.cacheProject(
            ProjectSummary(
                id: "project-1",
                revision: 4,
                name: "Current Name",
                ownerName: "owner@example.com",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 200),
                description: "",
                sharedUserCount: 0,
                roomScans: []
            )
        )

        try await applier.apply([
            SyncChange(
                resourceId: "project-1",
                operation: .upsert,
                revision: 1,
                syncStatus: "SYNCED",
                changedAt: Date(timeIntervalSince1970: 50),
                cursor: "c-stale",
                deletedAt: nil,
                resourceType: .project,
                payload: .project(
                    SyncProjectPayload(
                        id: "project-1",
                        ownerId: "user-1",
                        ownerEmail: "owner@example.com",
                        name: "Stale Name",
                        description: nil,
                        createdAt: Date(timeIntervalSince1970: 100),
                        updatedAt: Date(timeIntervalSince1970: 50),
                        lastSyncedAt: nil
                    )
                )
            )
        ])

        let project = try await localStore.fetchProject(id: "project-1")
        #expect(project.name == "Current Name")
        #expect(project.revision == 4)
    }
}
