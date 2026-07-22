//
//  MockProjectsService.swift
//  roomscan
//

import Foundation

actor MockProjectsService: ProjectsService {
    enum Scenario: Equatable, Sendable {
        case success
        case empty
        case projectsWithoutScans
        case failPage(Int)
    }

    private let scenario: Scenario
    private let projects: [ProjectSummary]
    private let simulatedDelayNanoseconds: UInt64

    init(
        scenario: Scenario = .success,
        projects: [ProjectSummary] = MockProjectsService.makeSeedProjects(),
        simulatedDelayNanoseconds: UInt64 = 150_000_000
    ) {
        self.scenario = scenario
        self.projects = projects.sorted { $0.updatedAt > $1.updatedAt }
        self.simulatedDelayNanoseconds = simulatedDelayNanoseconds
    }

    static func makeForCurrentProcess() -> MockProjectsService {
        let arguments = ProcessInfo.processInfo.arguments
        let delay: UInt64 = arguments.contains("-UITesting") ? 0 : 150_000_000

        if arguments.contains("-UITestProjectsEmpty") {
            return MockProjectsService(scenario: .empty, simulatedDelayNanoseconds: delay)
        }

        if arguments.contains("-UITestProjectsWithoutScans") {
            return MockProjectsService(scenario: .projectsWithoutScans, simulatedDelayNanoseconds: delay)
        }

        if arguments.contains("-UITestProjectsNextPageFails") {
            return MockProjectsService(scenario: .failPage(2), simulatedDelayNanoseconds: delay)
        }

        return MockProjectsService(simulatedDelayNanoseconds: delay)
    }

    func fetchProjects(page: Int, pageSize: Int) async throws -> ProjectPage {
        try await simulateDelay()

        if case .failPage(page) = scenario {
            throw ProjectsServiceError.network
        }

        let sourceProjects: [ProjectSummary]
        switch scenario {
        case .empty:
            sourceProjects = []
        case .projectsWithoutScans:
            sourceProjects = projectsWithoutScans
        case .success, .failPage:
            sourceProjects = projects
        }
        let startIndex = max(page - 1, 0) * pageSize
        guard startIndex < sourceProjects.count else {
            return ProjectPage(projects: [], hasMore: false)
        }

        let endIndex = min(startIndex + pageSize, sourceProjects.count)
        return ProjectPage(
            projects: Array(sourceProjects[startIndex..<endIndex]),
            hasMore: endIndex < sourceProjects.count
        )
    }

    nonisolated static func makeSeedProjects() -> [ProjectSummary] {
        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
        return (1...14).map { index in
            ProjectSummary(
                id: "project-\(index)",
                name: projectNames[index - 1],
                updatedAt: baseDate.addingTimeInterval(TimeInterval(-index * 3_600)),
                roomScans: makeRoomScans(projectIndex: index)
            )
        }
    }

    private nonisolated static let projectNames = [
        "Lakeside Remodel",
        "Downtown Loft",
        "Market Street Retail",
        "North Campus Suite",
        "Hillview Residence",
        "Atrium Office",
        "Garden Apartment",
        "Warehouse Conversion",
        "Harbor Guest House",
        "Pine Dental Clinic",
        "South Wing Lobby",
        "Cedar Workshop",
        "Ridgeview Kitchen",
        "Union Hall"
    ]

    private var projectsWithoutScans: [ProjectSummary] {
        projects.map {
            ProjectSummary(
                id: $0.id,
                name: $0.name,
                updatedAt: $0.updatedAt,
                roomScans: []
            )
        }
    }

    private nonisolated static func makeRoomScans(projectIndex: Int) -> [RoomScanSummary] {
        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
        let roomNames = [
            "Living Room",
            "Kitchen",
            "Primary Bedroom",
            "Guest Bath",
            "Entry Hall",
            "Office",
            "Dining Room"
        ]
        let count = 2 + (projectIndex % 6)

        return (0..<count).map { index in
            RoomScanSummary(
                id: "project-\(projectIndex)-scan-\(index + 1)",
                name: roomNames[index],
                createdAt: baseDate.addingTimeInterval(TimeInterval(-(projectIndex * 86_400 + index * 3_600))),
                thumbnailName: "thumbnail-\((projectIndex + index) % 5)",
                syncStatus: RoomScanSyncStatus.allCases[(projectIndex + index) % RoomScanSyncStatus.allCases.count],
                notes: makeNotes(projectIndex: projectIndex, scanIndex: index + 1)
            )
        }
    }

    private nonisolated static func makeNotes(projectIndex: Int, scanIndex: Int) -> [RoomScanNoteSummary] {
        let count = (projectIndex + scanIndex) % 3
        guard count > 0 else { return [] }

        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
        return (1...count).map { index in
            RoomScanNoteSummary(
                id: "project-\(projectIndex)-scan-\(scanIndex)-note-\(index)",
                text: "Note \(index)",
                createdAt: baseDate.addingTimeInterval(TimeInterval(-(projectIndex + scanIndex + index) * 600))
            )
        }
    }

    private func simulateDelay() async throws {
        guard simulatedDelayNanoseconds > 0 else { return }
        try await Task.sleep(nanoseconds: simulatedDelayNanoseconds)
    }
}
