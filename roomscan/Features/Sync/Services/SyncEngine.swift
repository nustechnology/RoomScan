//
//  SyncEngine.swift
//  roomscan
//

import Foundation

/// Pulls incremental `/sync/changes` pages and applies them to the local cache.
@MainActor
final class SyncEngine {
    nonisolated static let defaultPageLimit = 100
    nonisolated static let maximumPageLimit = 500
    private static let maximumPagesPerPull = 50

    private struct InFlightPull {
        let userId: String
        let task: Task<Int, Error>
    }

    private let syncService: any SyncService
    private let cursorStore: any SyncCursorStoring
    private let localCache: any ProjectsLocalCache
    private let sharedService: (any SharedService)?
    private let defaults: UserDefaults
    private var inFlightPull: InFlightPull?

    init(
        syncService: any SyncService,
        localCache: any ProjectsLocalCache,
        sharedService: (any SharedService)? = nil,
        cursorStore: any SyncCursorStoring = SyncCursorStore(),
        defaults: UserDefaults = .standard
    ) {
        self.syncService = syncService
        self.localCache = localCache
        self.sharedService = sharedService
        self.cursorStore = cursorStore
        self.defaults = defaults
    }

    @discardableResult
    func pullChanges(forUserId userId: String) async throws -> Int {
        if let inFlightPull, inFlightPull.userId == userId {
            return try await inFlightPull.task.value
        }
        if let inFlightPull {
            inFlightPull.task.cancel()
            _ = await inFlightPull.task.result
            self.inFlightPull = nil
        }

        let task = Task {
            try await self.performPull(forUserId: userId)
        }
        inFlightPull = InFlightPull(userId: userId, task: task)
        defer {
            if self.inFlightPull?.userId == userId {
                self.inFlightPull = nil
            }
        }
        return try await task.value
    }

    func clearCursor(forUserId userId: String) async {
        if let inFlightPull, inFlightPull.userId == userId {
            inFlightPull.task.cancel()
            _ = await inFlightPull.task.result
            self.inFlightPull = nil
        }
        await cursorStore.clear(forUserId: userId)
        SyncChangeApplier.clearIndexedState(forUserId: userId, defaults: defaults)
    }

    private func performPull(forUserId userId: String) async throws -> Int {
        var cursor = await cursorStore.cursor(forUserId: userId)
        var collected: [SyncChange] = []
        var pages = 0
        var didRecoverInvalidCursor = false
        var cursorToPersist = cursor
        let applier = SyncChangeApplier(
            localCache: localCache,
            sharedService: sharedService,
            currentUserID: userId,
            defaults: defaults
        )

        while pages < Self.maximumPagesPerPull {
            try Task.checkCancellation()
            let page = try await fetchPageRecoveringInvalidCursor(
                cursor: &cursor,
                didRecoverInvalidCursor: &didRecoverInvalidCursor,
                userId: userId
            )
            if didRecoverInvalidCursor, cursorToPersist != nil, pages == 0 {
                cursorToPersist = nil
            }
            try Task.checkCancellation()
            collected.append(contentsOf: page.changes)

            let next = page.nextCursor?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedNext = (next?.isEmpty == false) ? next : nil
            if let normalizedNext {
                cursorToPersist = normalizedNext
            } else if let lastChangeCursor = page.changes.compactMap(\.cursor).last {
                cursorToPersist = lastChangeCursor
            }
            pages += 1
            let reachedEnd = page.changes.isEmpty
                || normalizedNext == nil
                || normalizedNext == cursor
            cursor = normalizedNext
            if reachedEnd {
                break
            }
        }

        if !collected.isEmpty {
            try await applier.apply(collected)
        }
        try Task.checkCancellation()
        await cursorStore.save(cursor: cursorToPersist, forUserId: userId)
        return collected.count
    }

    private func fetchPageRecoveringInvalidCursor(
        cursor: inout String?,
        didRecoverInvalidCursor: inout Bool,
        userId: String
    ) async throws -> SyncChangesPage {
        do {
            return try await syncService.fetchChanges(
                cursor: cursor,
                since: nil,
                limit: Self.defaultPageLimit
            )
        } catch SyncServiceError.invalidRequest where cursor != nil && !didRecoverInvalidCursor {
            await cursorStore.clear(forUserId: userId)
            cursor = nil
            didRecoverInvalidCursor = true
            return try await syncService.fetchChanges(
                cursor: nil,
                since: nil,
                limit: Self.defaultPageLimit
            )
        }
    }
}
