//
//  MockSyncService.swift
//  roomscan
//

import Foundation

actor MockSyncService: SyncService {
    enum Scenario: Equatable, Sendable {
        case success
        case failLoad
    }

    private var items: [ProjectSyncStatusSummary]
    private var changePages: [[SyncChange]]
    private var scenario: Scenario
    private let simulatedDelayNanoseconds: UInt64
    private var changesCallCount = 0
    private var requestedChangesCursors: [String?] = []
    private var rejectInvalidCursorOnce: Bool
    /// When true, the last change page returns `nextCursor: nil` (API terminal page).
    private let nullTerminalNextCursor: Bool

    init(
        items: [ProjectSyncStatusSummary] = [],
        changePages: [[SyncChange]] = [],
        scenario: Scenario = .success,
        simulatedDelayNanoseconds: UInt64 = 0,
        rejectInvalidCursorOnce: Bool = false,
        nullTerminalNextCursor: Bool = false
    ) {
        self.items = items
        self.changePages = changePages
        self.scenario = scenario
        self.simulatedDelayNanoseconds = simulatedDelayNanoseconds
        self.rejectInvalidCursorOnce = rejectInvalidCursorOnce
        self.nullTerminalNextCursor = nullTerminalNextCursor
    }

    func setItems(_ items: [ProjectSyncStatusSummary]) {
        self.items = items
    }

    func setChangePages(_ pages: [[SyncChange]]) {
        self.changePages = pages
        self.changesCallCount = 0
    }

    func setScenario(_ scenario: Scenario) {
        self.scenario = scenario
    }

    func fetchSyncStatus(projectId: String?) async throws -> [ProjectSyncStatusSummary] {
        if simulatedDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: simulatedDelayNanoseconds)
        }

        switch scenario {
        case .failLoad:
            throw SyncServiceError.network
        case .success:
            if let projectId {
                return items.filter { $0.projectId == projectId }
            }
            return items
        }
    }

    func fetchChanges(
        cursor: String?,
        since: Date?,
        limit: Int
    ) async throws -> SyncChangesPage {
        _ = since
        _ = limit
        if simulatedDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: simulatedDelayNanoseconds)
        }

        switch scenario {
        case .failLoad:
            throw SyncServiceError.network
        case .success:
            requestedChangesCursors.append(cursor)
            if rejectInvalidCursorOnce, let cursor, !cursor.isEmpty {
                rejectInvalidCursorOnce = false
                throw SyncServiceError.invalidRequest
            }
            let index = changesCallCount
            changesCallCount += 1
            if changePages.isEmpty {
                return SyncChangesPage(changes: [], nextCursor: cursor)
            }
            guard index < changePages.count else {
                return SyncChangesPage(changes: [], nextCursor: cursor)
            }
            let changes = changePages[index]
            let nextCursor: String?
            if index + 1 < changePages.count {
                nextCursor = "cursor-\(index + 1)"
            } else if nullTerminalNextCursor {
                nextCursor = nil
            } else {
                nextCursor = "cursor-end"
            }
            return SyncChangesPage(changes: changes, nextCursor: nextCursor)
        }
    }

    func fetchChangesCallCount() -> Int {
        changesCallCount
    }

    func fetchChangesCursors() -> [String?] {
        requestedChangesCursors
    }

    static func makeForCurrentProcess() -> MockSyncService {
        MockSyncService(simulatedDelayNanoseconds: 0)
    }
}
