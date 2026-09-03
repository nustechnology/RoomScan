//
//  MockSharedService.swift
//  roomscan
//

import Foundation

actor MockSharedService: SharedService {
    enum Scenario: Equatable, Sendable {
        case success
        case empty
        case failLoad
    }

    private var scenario: Scenario
    private var projects: [SharedProjectItem]
    private var scans: [SharedScanItem]
    private let simulatedDelayNanoseconds: UInt64
    private let now: Date

    init(
        scenario: Scenario = .success,
        projects: [SharedProjectItem]? = nil,
        scans: [SharedScanItem]? = nil,
        simulatedDelayNanoseconds: UInt64 = 150_000_000,
        now: Date = Date()
    ) {
        self.scenario = scenario
        self.now = now
        self.projects = projects ?? MockSharedSeedData.makeSeedProjects(now: now)
        self.scans = scans ?? MockSharedSeedData.makeSeedScans(now: now)
        self.simulatedDelayNanoseconds = simulatedDelayNanoseconds
    }

    func setScenario(_ scenario: Scenario) {
        self.scenario = scenario
    }

    static func makeForCurrentProcess() -> MockSharedService {
        let arguments = ProcessInfo.processInfo.arguments
        let delay: UInt64 = arguments.contains("-UITesting") ? 0 : 150_000_000

        if arguments.contains("-UITestSharedEmpty") {
            return MockSharedService(scenario: .empty, simulatedDelayNanoseconds: delay)
        }

        if arguments.contains("-UITestSharedFail") {
            return MockSharedService(scenario: .failLoad, simulatedDelayNanoseconds: delay)
        }

        return MockSharedService(simulatedDelayNanoseconds: delay)
    }

    nonisolated static func makeSeedProjects(now: Date = Date()) -> [SharedProjectItem] {
        MockSharedSeedData.makeSeedProjects(now: now)
    }

    nonisolated static func makeSeedScans(now: Date = Date()) -> [SharedScanItem] {
        MockSharedSeedData.makeSeedScans(now: now)
    }

    func fetchSharedProjects() async throws -> [SharedProjectItem] {
        try await simulateDelay()
        try throwIfFailed()

        if scenario == .empty {
            return []
        }

        return projects.filter {
            SharedInactiveRetention.shouldRetain(
                status: $0.status,
                statusChangedAt: $0.statusChangedAt,
                now: now
            )
        }
    }

    func fetchSharedScans() async throws -> [SharedScanItem] {
        try await simulateDelay()
        try throwIfFailed()

        if scenario == .empty {
            return []
        }

        return scans.filter {
            SharedInactiveRetention.shouldRetain(
                status: $0.status,
                statusChangedAt: $0.statusChangedAt,
                now: now
            )
        }
    }

    func removeSharedItem(id: String, scope: SharedItemScope) async throws {
        try await simulateDelay()
        try throwIfFailed()

        switch scope {
        case .project:
            guard projects.contains(where: { $0.id == id }) else {
                throw SharedServiceError.notFound
            }
            projects.removeAll { $0.id == id }
        case .scan:
            guard scans.contains(where: { $0.id == id }) else {
                throw SharedServiceError.notFound
            }
            scans.removeAll { $0.id == id }
        }
    }

    func ingestSharedProject(_ project: SharedProjectItem) async throws {
        try await simulateDelay()
        try throwIfFailed()
        let existing = projects.first { $0.id == project.id }
        let merged = SharedProjectItem.coalescing(existing: existing, incoming: project)
        projects.removeAll { $0.id == project.id }
        projects.insert(merged, at: 0)
        if scenario == .empty {
            scenario = .success
        }
    }

    func ingestSharedScan(_ scan: SharedScanItem) async throws {
        try await simulateDelay()
        try throwIfFailed()
        let existing = scans.first { $0.id == scan.id }
        let merged = SharedScanItem.coalescing(existing: existing, incoming: scan)
        scans.removeAll { $0.id == scan.id }
        scans.insert(merged, at: 0)
        if scenario == .empty {
            scenario = .success
        }
    }

    private func throwIfFailed() throws {
        if scenario == .failLoad {
            throw SharedServiceError.network
        }
    }

    private func simulateDelay() async throws {
        guard simulatedDelayNanoseconds > 0 else { return }
        try await Task.sleep(nanoseconds: simulatedDelayNanoseconds)
    }
}
