//
//  SyncChangeApplier.swift
//  roomscan
//

import Foundation

/// Applies normalized `/sync/changes` payloads onto the local projects cache.
@MainActor
final class SyncChangeApplier {
    let localCache: any ProjectsLocalCache
    let sharedService: (any SharedService)?
    let revisionStore: APIRevisionStore
    let currentUserID: String?
    let indexStore: SyncIndexStore

    init(
        localCache: any ProjectsLocalCache,
        sharedService: (any SharedService)? = nil,
        revisionStore: APIRevisionStore = .shared,
        currentUserID: String? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.localCache = localCache
        self.sharedService = sharedService
        self.revisionStore = revisionStore
        self.currentUserID = currentUserID
        self.indexStore = SyncIndexStore(userId: currentUserID, defaults: defaults)
    }

    static func clearIndexedState(forUserId userId: String, defaults: UserDefaults) {
        SyncIndexStore.clear(forUserId: userId, defaults: defaults)
    }

    func apply(_ changes: [SyncChange]) async throws {
        for change in Self.sortedForApply(changes) {
            try Task.checkCancellation()
            do {
                try await apply(change)
            } catch SyncApplyError.missingParent, SyncApplyError.incompleteChange {
                continue
            }
        }
    }

    /// Rank parent/child within each contiguous run of the same operation.
    /// Received order across operation boundaries is preserved so a DELETE then
    /// UPSERT of the same local slot (re-add access, replace MODEL) is not inverted.
    nonisolated static func sortedForApply(_ changes: [SyncChange]) -> [SyncChange] {
        var result: [SyncChange] = []
        result.reserveCapacity(changes.count)
        var start = changes.startIndex
        while start < changes.endIndex {
            let operation = changes[start].operation
            var end = changes.index(after: start)
            while end < changes.endIndex, changes[end].operation == operation {
                end = changes.index(after: end)
            }
            let run = changes[start..<end]
            result.append(contentsOf: rankedRun(run))
            start = end
        }
        return result
    }

    /// UPSERT parents before children; DELETE children before parents. Stable for ties.
    private nonisolated static func rankedRun(_ run: ArraySlice<SyncChange>) -> [SyncChange] {
        run.enumerated()
            .sorted { lhs, rhs in
                let left = applyRank(lhs.element)
                let right = applyRank(rhs.element)
                if left != right { return left < right }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private nonisolated static func applyRank(_ change: SyncChange) -> Int {
        let upsertRank: [SyncResourceType: Int] = [
            .project: 0,
            .projectAccess: 1,
            .scan: 2,
            .scanAsset: 3,
            .note: 4
        ]
        let deleteRank: [SyncResourceType: Int] = [
            .note: 10,
            .scanAsset: 11,
            .scan: 12,
            .projectAccess: 13,
            .project: 14
        ]
        switch change.operation {
        case .upsert:
            return upsertRank[change.resourceType] ?? 4
        case .delete:
            return deleteRank[change.resourceType] ?? 14
        }
    }

    private func apply(_ change: SyncChange) async throws {
        switch change.operation {
        case .delete:
            try await applyDelete(change)
        case .upsert:
            try await applyUpsert(change)
        }
        await revisionStore.update(change.revision.map(String.init), for: change.resourceId)
    }

    private func applyDelete(_ change: SyncChange) async throws {
        switch change.resourceType {
        case .project:
            try await deleteIgnoringNotFound {
                try await localCache.deleteProject(id: change.resourceId)
            }
        case .scan:
            if let project = await projectContainingScan(id: change.resourceId) {
                try await deleteIgnoringNotFound {
                    try await localCache.deleteScan(projectID: project.id, scanID: change.resourceId)
                }
            }
        case .note:
            try await removeNote(id: change.resourceId)
        case .scanAsset:
            try await applyScanAssetDelete(change)
        case .projectAccess:
            try await applyProjectAccessDelete(change)
        }
    }

    private func applyUpsert(_ change: SyncChange) async throws {
        guard let payload = change.payload else {
            throw SyncApplyError.incompleteChange
        }

        switch payload {
        case let .project(project):
            try await upsertProject(project, revision: change.revision)
        case let .scan(scan):
            try await upsertScan(scan, changeSyncStatus: change.syncStatus)
        case let .note(note):
            try await upsertNote(note)
        case let .scanAsset(asset):
            try await upsertScanAsset(asset, changeSyncStatus: change.syncStatus)
        case let .projectAccess(access):
            try await upsertProjectAccess(access)
        }
    }

    private func upsertProject(_ payload: SyncProjectPayload, revision: Int?) async throws {
        let existing = try? await localCache.fetchProject(id: payload.id)
        // Unknown wire revision cannot be proven stale — apply rather than drop.
        if let revision, let existing, existing.revision > revision {
            return
        }

        let updatedAt = payload.updatedAt ?? existing?.updatedAt ?? payload.createdAt
        let summary = ProjectSummary(
            id: payload.id,
            revision: revision ?? existing?.revision ?? 1,
            name: payload.name,
            ownerName: payload.ownerEmail.flatMap { $0.isEmpty ? nil : $0 } ?? existing?.ownerName ?? "You",
            createdAt: payload.createdAt,
            updatedAt: updatedAt,
            description: payload.description ?? "",
            sharedUserCount: existing?.sharedUserCount ?? 0,
            roomScans: existing?.roomScans ?? [],
            scanCount: existing?.scanCount
        )
        try await persistCachedProject(summary)

        if isSharedWithCurrentUser(ownerId: payload.ownerId) {
            try? await sharedService?.ingestSharedProject(
                SharedProjectItem.make(
                    from: summary,
                    status: .active,
                    statusChangedAt: updatedAt
                )
            )
        }
    }

    private func upsertScan(_ payload: SyncScanPayload, changeSyncStatus: String?) async throws {
        let existingProject = try? await localCache.fetchProject(id: payload.projectId)
        let existingScan = existingProject?.roomScans.first(where: { $0.id == payload.id })

        let remoteStatus = RoomScanSyncStatus.fromAPI(changeSyncStatus ?? payload.syncStatus)
        let preferredStatus = ProjectAPIMapping.preferredSyncStatus(
            local: existingScan?.syncStatus ?? remoteStatus,
            remote: remoteStatus,
            hasLocalUploadArtifacts: existingScan?.hasLocalUploadArtifacts ?? false
        )

        let scan = RoomScanSummary(
            id: payload.id,
            name: payload.name,
            createdAt: payload.createdAt,
            localModelURL: existingScan?.localModelURL,
            thumbnailName: existingScan?.thumbnailName ?? "",
            syncStatus: preferredStatus,
            creatorUserID: payload.createdById ?? existingScan?.creatorUserID ?? "",
            creatorDisplayName: payload.creatorEmail ?? existingScan?.creatorDisplayName ?? "",
            notes: existingScan?.notes ?? [],
            meshPath: existingScan?.meshPath ?? "",
            thumbnailPath: payload.thumbnail ?? existingScan?.thumbnailPath ?? "",
            noteCount: existingScan?.noteCount ?? existingScan?.notes.count ?? 0
        )

        guard var project = existingProject else {
            throw SyncApplyError.missingParent
        }

        if let replaced = project.replacingScan(scan, updatedAt: payload.updatedAt ?? Date()) {
            project = replaced
        } else {
            var scans = project.roomScans
            scans.insert(scan, at: 0)
            project = project.withRoomScans(scans, updatedAt: payload.updatedAt ?? Date(), scanCountDelta: 1)
        }
        try await persistCachedProject(project)
    }
}
