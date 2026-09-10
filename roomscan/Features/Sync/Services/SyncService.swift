//
//  SyncService.swift
//  roomscan
//

import Foundation

nonisolated protocol SyncService: Sendable {
    /// Backend-known sync readiness for every accessible project, or one project when `projectId` is set.
    func fetchSyncStatus(projectId: String?) async throws -> [ProjectSyncStatusSummary]

    /// Pull a page of visible resource changes. Omit `cursor`/`since` for the initial snapshot.
    func fetchChanges(
        cursor: String?,
        since: Date?,
        limit: Int
    ) async throws -> SyncChangesPage
}

extension SyncService {
    func fetchSyncStatus() async throws -> [ProjectSyncStatusSummary] {
        try await fetchSyncStatus(projectId: nil)
    }

    func fetchChanges(cursor: String? = nil, since: Date? = nil) async throws -> SyncChangesPage {
        try await fetchChanges(cursor: cursor, since: since, limit: SyncEngine.defaultPageLimit)
    }
}
