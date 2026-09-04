//
//  SyncChangeApplier+Resources.swift
//  roomscan
//

import Foundation

extension SyncChangeApplier {
    func upsertNote(_ payload: SyncNotePayload) async throws {
        guard let project = await projectContainingScan(id: payload.scanId),
              let existingScan = project.roomScans.first(where: { $0.id == payload.scanId }) else {
            throw SyncApplyError.missingParent
        }

        let noteText = [payload.title, payload.content]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        var notes = existingScan.notes.filter { $0.id != payload.id }
        notes.append(
            RoomScanNoteSummary(
                id: payload.id,
                text: noteText.isEmpty ? (payload.content ?? payload.title ?? "") : noteText,
                createdAt: payload.createdAt
            )
        )
        notes.sort { $0.createdAt > $1.createdAt }

        let updatedScan = existingScan.replacingNotes(notes, noteCount: max(existingScan.noteCount, notes.count))
        guard let updatedProject = project.replacingScan(updatedScan, updatedAt: payload.updatedAt ?? Date()) else {
            throw SyncApplyError.persistFailed
        }
        try await persistCachedProject(updatedProject)
    }

    func removeNote(id noteID: String) async throws {
        let projects = try await localCache.fetchAllProjectsSortedByUpdated()
        for project in projects {
            guard let scan = project.roomScans.first(where: { $0.notes.contains(where: { $0.id == noteID }) }) else {
                continue
            }
            let notes = scan.notes.filter { $0.id != noteID }
            let removedCount = scan.notes.count - notes.count
            let updatedScan = scan.replacingNotes(
                notes,
                noteCount: max(notes.count, scan.noteCount - removedCount)
            )
            if let updatedProject = project.replacingScan(updatedScan) {
                try await persistCachedProject(updatedProject)
            }
            return
        }
    }

    func upsertScanAsset(_ payload: SyncScanAssetPayload, changeSyncStatus: String?) async throws {
        indexStore.rememberAsset(id: payload.id, scanId: payload.scanId, assetType: payload.assetType)
        guard let project = await projectContainingScan(id: payload.scanId),
              let existingScan = project.roomScans.first(where: { $0.id == payload.scanId }) else {
            throw SyncApplyError.missingParent
        }

        let remoteStatus = RoomScanSyncStatus.fromAPI(changeSyncStatus ?? payload.status)
        let nextStatus = ProjectAPIMapping.preferredSyncStatus(
            local: existingScan.syncStatus,
            remote: remoteStatus,
            hasLocalUploadArtifacts: existingScan.hasLocalUploadArtifacts
        )
        guard nextStatus != existingScan.syncStatus else { return }

        let updatedScan = existingScan.replacingSyncStatus(nextStatus)
        if let updatedProject = project.replacingScan(updatedScan) {
            try await persistCachedProject(updatedProject)
        }
    }

    func applyScanAssetDelete(_ change: SyncChange) async throws {
        let scanId: String
        let assetType: String?
        let assetId: String
        if let payload = change.payload, case let .scanAsset(asset) = payload {
            scanId = asset.scanId
            assetType = asset.assetType
            assetId = asset.id
        } else if let remembered = indexStore.rememberedAsset(forAssetId: change.resourceId) {
            scanId = remembered.scanId
            assetType = remembered.assetType
            assetId = change.resourceId
        } else {
            return
        }

        let isLive = indexStore.isLiveAsset(id: assetId, scanId: scanId, assetType: assetType)
        if isLive {
            guard let project = await projectContainingScan(id: scanId),
                  let existingScan = project.roomScans.first(where: { $0.id == scanId }),
                  let updatedScan = existingScan.clearingAsset(ofType: assetType),
                  let updatedProject = project.replacingScan(updatedScan) else {
                return
            }
            try await persistCachedProject(updatedProject)
            indexStore.clearLiveAsset(scanId: scanId, assetType: assetType, matching: assetId)
        }
        indexStore.forgetAsset(id: assetId)
    }

    func upsertProjectAccess(_ access: SyncProjectAccessPayload) async throws {
        indexStore.rememberAccess(access)
        guard isCurrentUser(access.userId), !isOwnerRole(access.role) else { return }
        try await ingestSharedProject(
            projectId: access.projectId,
            status: .active,
            statusChangedAt: access.updatedAt ?? access.acceptedAt ?? access.createdAt ?? Date()
        )
    }

    func applyProjectAccessDelete(_ change: SyncChange) async throws {
        let projectId: String
        let userId: String
        let accessId: String
        let role: String?
        if let payload = change.payload, case let .projectAccess(access) = payload {
            projectId = access.projectId
            userId = access.userId
            accessId = access.id
            role = access.role
        } else if let record = indexStore.rememberedAccess(id: change.resourceId) {
            projectId = record.projectId
            userId = record.userId
            accessId = change.resourceId
            role = record.role
        } else {
            return
        }

        guard isCurrentUser(userId) else {
            indexStore.forgetAccess(id: accessId)
            return
        }
        if isOwnerRole(role) {
            indexStore.forgetAccess(id: accessId)
            return
        }
        try await ingestSharedProject(
            projectId: projectId,
            status: .accessRevoked,
            statusChangedAt: change.deletedAt ?? change.changedAt ?? Date()
        )
        indexStore.forgetAccess(id: accessId)
    }

    func ingestSharedProject(
        projectId: String,
        status: SharedAccessStatus,
        statusChangedAt: Date
    ) async throws {
        guard let sharedService else { return }
        let project = try? await localCache.fetchProject(id: projectId)
        let item: SharedProjectItem
        if let project {
            item = SharedProjectItem.make(
                from: project,
                status: status,
                statusChangedAt: statusChangedAt,
                includeDetail: status.isActive
            )
        } else if status.isActive {
            // Avoid Active stubs with empty name / nil detail. Those overwrite a prior
            // invitation-accept ingest and make Shared With Me cards silently untappable.
            // Remote shared-projects fetch (or the accept destination) supplies openable detail.
            return
        } else {
            item = SharedProjectItem(
                id: projectId,
                name: "",
                ownerName: "",
                scanCount: 0,
                thumbnailName: nil,
                status: status,
                statusChangedAt: statusChangedAt,
                detailProject: nil
            )
        }
        do {
            try await sharedService.ingestSharedProject(item)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SyncApplyError.persistFailed
        }
    }

    func persistCachedProject(_ project: ProjectSummary) async throws {
        do {
            try await localCache.replaceCachedProject(project)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SyncApplyError.persistFailed
        }
    }

    func deleteIgnoringNotFound(_ operation: () async throws -> Void) async throws {
        do {
            try await operation()
        } catch is CancellationError {
            throw CancellationError()
        } catch ProjectsServiceError.projectNotFound, ProjectsServiceError.notFound {
            return
        } catch {
            throw SyncApplyError.persistFailed
        }
    }

    func projectContainingScan(id scanID: String) async -> ProjectSummary? {
        let projects = (try? await localCache.fetchAllProjectsSortedByUpdated()) ?? []
        return projects.first { project in
            project.roomScans.contains(where: { $0.id == scanID })
        }
    }

    func isSharedWithCurrentUser(ownerId: String?) -> Bool {
        guard let currentUserID, let ownerId, !ownerId.isEmpty else { return false }
        return ownerId != currentUserID
    }

    func isCurrentUser(_ userId: String) -> Bool {
        guard let currentUserID else { return false }
        return userId == currentUserID
    }

    func isOwnerRole(_ role: String?) -> Bool {
        role?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "OWNER"
    }
}

extension RoomScanSummary {
    fileprivate func replacingNotes(_ notes: [RoomScanNoteSummary], noteCount: Int) -> RoomScanSummary {
        RoomScanSummary(
            id: id,
            name: name,
            createdAt: createdAt,
            localModelURL: localModelURL,
            thumbnailName: thumbnailName,
            syncStatus: syncStatus,
            creatorUserID: creatorUserID,
            creatorDisplayName: creatorDisplayName,
            notes: notes,
            meshPath: meshPath,
            thumbnailPath: thumbnailPath,
            noteCount: noteCount
        )
    }

    fileprivate func replacingSyncStatus(_ syncStatus: RoomScanSyncStatus) -> RoomScanSummary {
        RoomScanSummary(
            id: id,
            name: name,
            createdAt: createdAt,
            localModelURL: localModelURL,
            thumbnailName: thumbnailName,
            syncStatus: syncStatus,
            creatorUserID: creatorUserID,
            creatorDisplayName: creatorDisplayName,
            notes: notes,
            meshPath: meshPath,
            thumbnailPath: thumbnailPath,
            noteCount: noteCount
        )
    }

    fileprivate func clearingAsset(ofType assetType: String?) -> RoomScanSummary? {
        switch assetType?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "MODEL":
            return RoomScanSummary(
                id: id,
                name: name,
                createdAt: createdAt,
                localModelURL: localModelURL,
                thumbnailName: thumbnailName,
                syncStatus: syncStatus,
                creatorUserID: creatorUserID,
                creatorDisplayName: creatorDisplayName,
                notes: notes,
                meshPath: "",
                thumbnailPath: thumbnailPath,
                noteCount: noteCount
            )
        case "THUMBNAIL":
            return RoomScanSummary(
                id: id,
                name: name,
                createdAt: createdAt,
                localModelURL: localModelURL,
                thumbnailName: thumbnailName,
                syncStatus: syncStatus,
                creatorUserID: creatorUserID,
                creatorDisplayName: creatorDisplayName,
                notes: notes,
                meshPath: meshPath,
                thumbnailPath: "",
                noteCount: noteCount
            )
        default:
            // Unknown or missing type: do not wipe unrelated artifacts.
            return nil
        }
    }
}
