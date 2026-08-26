//
//  SyncEngineCursorTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

@MainActor
struct SyncEngineCursorTests {
    @Test func pullChangesAppliesProjectAndScanUpsertsAndPersistsCursor() async throws {
        let localStore = SyncTestFixtures.makeLocalStore()
        var projectChange = SyncTestFixtures.makeProjectChange(id: "project-1", name: "Synced Project")
        projectChange = SyncChange(
            resourceId: projectChange.resourceId,
            operation: projectChange.operation,
            revision: 2,
            syncStatus: projectChange.syncStatus,
            changedAt: projectChange.changedAt,
            cursor: "c1",
            deletedAt: projectChange.deletedAt,
            resourceType: projectChange.resourceType,
            payload: .project(
                SyncProjectPayload(
                    id: "project-1",
                    ownerId: "user-1",
                    ownerEmail: "owner@example.com",
                    name: "Synced Project",
                    description: "From sync",
                    createdAt: Date(timeIntervalSince1970: 100),
                    updatedAt: Date(timeIntervalSince1970: 200),
                    lastSyncedAt: Date(timeIntervalSince1970: 200)
                )
            )
        )
        let scanChange = try SyncTestFixtures.makeScanChange(
            id: "scan-1",
            projectId: "project-1",
            name: "Kitchen",
            cursor: "c2"
        )
        let defaults = UserDefaults(suiteName: "SyncEngineTests.\(UUID().uuidString)")!
        let cursorStore = SyncCursorStore(defaults: defaults)
        let engine = SyncEngine(
            syncService: MockSyncService(
                changePages: [[projectChange, scanChange]],
                simulatedDelayNanoseconds: 0
            ),
            localCache: localStore,
            cursorStore: cursorStore
        )

        let applied = try await engine.pullChanges(forUserId: "user-1")

        #expect(applied == 2)
        let project = try await localStore.fetchProject(id: "project-1")
        #expect(project.name == "Synced Project")
        #expect(project.roomScans.count == 1)
        #expect(project.roomScans.first?.name == "Kitchen")
        #expect(await cursorStore.cursor(forUserId: "user-1") == "cursor-end")
    }
    @Test func pullChangesClearsInvalidCursorAndRetriesSnapshot() async throws {
        let localStore = SyncTestFixtures.makeLocalStore()
        let defaults = UserDefaults(suiteName: "SyncEngineTests.\(UUID().uuidString)")!
        let cursorStore = SyncCursorStore(defaults: defaults)
        await cursorStore.save(cursor: "stale-cursor", forUserId: "user-1")

        let syncService = MockSyncService(
            changePages: [[SyncTestFixtures.makeProjectChange(id: "project-recovered", name: "Recovered")]],
            simulatedDelayNanoseconds: 0,
            rejectInvalidCursorOnce: true
        )
        let engine = SyncEngine(
            syncService: syncService,
            localCache: localStore,
            cursorStore: cursorStore,
            defaults: defaults
        )

        let applied = try await engine.pullChanges(forUserId: "user-1")

        #expect(applied == 1)
        #expect(try await localStore.fetchProject(id: "project-recovered").name == "Recovered")
        #expect(await cursorStore.cursor(forUserId: "user-1") == "cursor-end")
        let cursors = await syncService.fetchChangesCursors()
        #expect(cursors.first == "stale-cursor")
        #expect(cursors.contains(where: { $0 == nil }))
    }

    @Test func pullChangesDoesNotRestoreRejectedCursorAfterTerminalRecoveryPage() async throws {
        let localStore = SyncTestFixtures.makeLocalStore()
        let defaults = UserDefaults(suiteName: "SyncEngineTests.\(UUID().uuidString)")!
        let cursorStore = SyncCursorStore(defaults: defaults)
        await cursorStore.save(cursor: "stale-cursor", forUserId: "user-1")

        let base = SyncTestFixtures.makeProjectChange(id: "project-recovered", name: "Recovered")
        let changeWithoutCursor = SyncChange(
            resourceId: base.resourceId,
            operation: base.operation,
            revision: base.revision,
            syncStatus: base.syncStatus,
            changedAt: base.changedAt,
            cursor: nil,
            deletedAt: base.deletedAt,
            resourceType: base.resourceType,
            payload: base.payload
        )
        let syncService = MockSyncService(
            changePages: [[changeWithoutCursor]],
            simulatedDelayNanoseconds: 0,
            rejectInvalidCursorOnce: true,
            nullTerminalNextCursor: true
        )
        let engine = SyncEngine(
            syncService: syncService,
            localCache: localStore,
            cursorStore: cursorStore,
            defaults: defaults
        )

        let applied = try await engine.pullChanges(forUserId: "user-1")

        #expect(applied == 1)
        #expect(try await localStore.fetchProject(id: "project-recovered").name == "Recovered")
        #expect(await cursorStore.cursor(forUserId: "user-1") == nil)
        let cursors = await syncService.fetchChangesCursors()
        #expect(cursors.first == "stale-cursor")
        #expect(cursors.contains(where: { $0 == nil }))
    }

    @Test func pullChangesCoalescesConcurrentCalls() async throws {
        let localStore = SyncTestFixtures.makeLocalStore()
        let syncService = MockSyncService(
            changePages: [[SyncTestFixtures.makeProjectChange(id: "project-1", name: "Once")]],
            simulatedDelayNanoseconds: 80_000_000
        )
        let engine = SyncEngine(
            syncService: syncService,
            localCache: localStore,
            cursorStore: SyncCursorStore(defaults: UserDefaults(suiteName: "SyncEngineTests.\(UUID().uuidString)")!)
        )

        async let first = engine.pullChanges(forUserId: "user-1")
        async let second = engine.pullChanges(forUserId: "user-1")
        let counts = try await (first, second)

        #expect(counts.0 == 1)
        #expect(counts.1 == 1)
        #expect(await syncService.fetchChangesCallCount() == 2)
    }
    @Test func clearCursorRemovesStoredCursor() async {
        let defaults = UserDefaults(suiteName: "SyncEngineTests.\(UUID().uuidString)")!
        let cursorStore = SyncCursorStore(defaults: defaults)
        await cursorStore.save(cursor: "keep-me", forUserId: "user-1")
        let engine = SyncEngine(
            syncService: MockSyncService(simulatedDelayNanoseconds: 0),
            localCache: SyncTestFixtures.makeLocalStore(),
            cursorStore: cursorStore
        )

        await engine.clearCursor(forUserId: "user-1")

        #expect(await cursorStore.cursor(forUserId: "user-1") == nil)
    }
    @Test func noteUpsertWithoutParentIsSkippedAndCursorStillAdvances() async throws {
        let localStore = SyncTestFixtures.makeLocalStore()
        let defaults = UserDefaults(suiteName: "SyncEngineTests.\(UUID().uuidString)")!
        let cursorStore = SyncCursorStore(defaults: defaults)
        let engine = SyncEngine(
            syncService: MockSyncService(
                changePages: [[SyncTestFixtures.makeNoteChange(id: "note-orphan", scanId: "missing-scan")]],
                simulatedDelayNanoseconds: 0
            ),
            localCache: localStore,
            cursorStore: cursorStore,
            defaults: defaults
        )

        let applied = try await engine.pullChanges(forUserId: "user-1")

        #expect(applied == 1)
        #expect(await cursorStore.cursor(forUserId: "user-1") == "cursor-end")
    }
    @Test func pullChangesAppliesNoteFromEarlierPageOnceParentArrivesLater() async throws {
        let localStore = SyncTestFixtures.makeLocalStore()
        let defaults = UserDefaults(suiteName: "SyncEngineTests.\(UUID().uuidString)")!
        let cursorStore = SyncCursorStore(defaults: defaults)
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
        let engine = SyncEngine(
            syncService: MockSyncService(
                changePages: [
                    [SyncTestFixtures.makeNoteChange(id: "note-1", scanId: "scan-1")],
                    [scanChange, SyncTestFixtures.makeProjectChange(id: "project-1", name: "Home")]
                ],
                simulatedDelayNanoseconds: 0
            ),
            localCache: localStore,
            cursorStore: cursorStore,
            defaults: defaults
        )

        let applied = try await engine.pullChanges(forUserId: "user-1")

        #expect(applied == 3)
        let project = try await localStore.fetchProject(id: "project-1")
        #expect(project.roomScans.first?.notes.contains(where: { $0.id == "note-1" }) == true)
        #expect(await cursorStore.cursor(forUserId: "user-1") == "cursor-end")
    }
    @Test func clearCursorRemovesUserScopedAccessIndex() async throws {
        let localStore = SyncTestFixtures.makeLocalStore()
        let defaults = UserDefaults(suiteName: "SyncEngineTests.\(UUID().uuidString)")!
        let sharedService = MockSharedService(projects: [], scans: [], simulatedDelayNanoseconds: 0)
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
        let accessKey = "sync.projectAccess.user-1.access-1"
        #expect(defaults.data(forKey: accessKey) != nil)

        let engine = SyncEngine(
            syncService: MockSyncService(simulatedDelayNanoseconds: 0),
            localCache: localStore,
            cursorStore: SyncCursorStore(defaults: defaults),
            defaults: defaults
        )
        await engine.clearCursor(forUserId: "user-1")

        #expect(defaults.data(forKey: accessKey) == nil)
    }

    @Test func pullChangesPersistsLastChangeCursorWhenNextCursorIsNull() async throws {
        let localStore = SyncTestFixtures.makeLocalStore()
        let defaults = UserDefaults(suiteName: "SyncEngineCursorTests.\(UUID().uuidString)")!
        let cursorStore = SyncCursorStore(defaults: defaults)
        await cursorStore.save(cursor: "prior-cursor", forUserId: "user-1")

        let syncService = MockSyncService(
            changePages: [[SyncTestFixtures.makeProjectChange(id: "project-null-next", name: "Null Next")]],
            simulatedDelayNanoseconds: 0,
            nullTerminalNextCursor: true
        )
        let engine = SyncEngine(
            syncService: syncService,
            localCache: localStore,
            cursorStore: cursorStore,
            defaults: defaults
        )

        let applied = try await engine.pullChanges(forUserId: "user-1")

        #expect(applied == 1)
        #expect(await cursorStore.cursor(forUserId: "user-1") == "c-project-null-next")
    }

    @Test func pullChangesKeepsPriorCursorWhenNullNextHasNoChangeCursors() async throws {
        let localStore = SyncTestFixtures.makeLocalStore()
        let defaults = UserDefaults(suiteName: "SyncEngineCursorTests.\(UUID().uuidString)")!
        let cursorStore = SyncCursorStore(defaults: defaults)
        await cursorStore.save(cursor: "prior-cursor", forUserId: "user-1")

        let base = SyncTestFixtures.makeProjectChange(id: "project-no-cursor", name: "No Cursor")
        let change = SyncChange(
            resourceId: base.resourceId,
            operation: base.operation,
            revision: base.revision,
            syncStatus: base.syncStatus,
            changedAt: base.changedAt,
            cursor: nil,
            deletedAt: base.deletedAt,
            resourceType: base.resourceType,
            payload: base.payload
        )
        let syncService = MockSyncService(
            changePages: [[change]],
            simulatedDelayNanoseconds: 0,
            nullTerminalNextCursor: true
        )
        let engine = SyncEngine(
            syncService: syncService,
            localCache: localStore,
            cursorStore: cursorStore,
            defaults: defaults
        )

        let applied = try await engine.pullChanges(forUserId: "user-1")

        #expect(applied == 1)
        #expect(await cursorStore.cursor(forUserId: "user-1") == "prior-cursor")
    }
}
