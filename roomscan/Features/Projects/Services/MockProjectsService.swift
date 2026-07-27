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
    private var projects: [ProjectSummary]
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

        let sourceProjects = sourceProjectsForScenario()

        guard page >= 1, pageSize > 0 else {
            throw ProjectsServiceError.invalidPagination
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

    func updateProject(id: String, name: String, description: String) async throws -> ProjectSummary {
        try await simulateDelay()

        guard let index = projects.firstIndex(where: { $0.id == id }) else {
            throw ProjectsServiceError.notFound
        }

        let existing = projects[index]
        let updated = ProjectSummary(
            id: existing.id,
            name: name,
            ownerName: existing.ownerName,
            createdAt: existing.createdAt,
            updatedAt: Date(),
            description: description,
            sharedUserCount: existing.sharedUserCount,
            roomScans: existing.roomScans
        )
        projects[index] = updated
        projects.sort { $0.updatedAt > $1.updatedAt }
        return updated
    }

    func deleteProject(id: String) async throws {
        try await simulateDelay()

        guard projects.contains(where: { $0.id == id }) else {
            throw ProjectsServiceError.notFound
        }

        projects.removeAll { $0.id == id }
    }

    nonisolated static func makeSeedProjects() -> [ProjectSummary] {
        let baseDate = fixtureBaseDate
        return (1...14).map { index in
            ProjectSummary(
                id: "project-\(index)",
                name: projectNames[index - 1],
                ownerName: "You",
                createdAt: baseDate.addingTimeInterval(TimeInterval(-index * 86_400)),
                updatedAt: baseDate.addingTimeInterval(TimeInterval(-index * 3_600)),
                description: "",
                sharedUserCount: 4,
                roomScans: makeRoomScans(projectIndex: index)
            )
        }
    }

    private nonisolated static let fixtureBaseDate = Date(timeIntervalSince1970: 1_750_000_000)

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

    private func sourceProjectsForScenario() -> [ProjectSummary] {
        switch scenario {
        case .empty:
            return []
        case .projectsWithoutScans:
            return projects.map {
                ProjectSummary(
                    id: $0.id,
                    name: $0.name,
                    ownerName: $0.ownerName,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    description: $0.description,
                    sharedUserCount: $0.sharedUserCount,
                    roomScans: []
                )
            }
        case .success, .failPage:
            return projects
        }
    }

    private nonisolated static func makeRoomScans(projectIndex: Int) -> [RoomScanSummary] {
        let baseDate = fixtureBaseDate
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
            let scanNumber = index + 1
            let scanID = "project-\(projectIndex)-scan-\(scanNumber)"
            let createdAt = baseDate.addingTimeInterval(
                TimeInterval(-(projectIndex * 86_400 + index * 3_600))
            )
            let thumbnailName = "thumbnail-\((projectIndex + index) % 5)"
            let syncStatusIndex = (projectIndex + index) % RoomScanSyncStatus.allCases.count
            let syncStatus = RoomScanSyncStatus.allCases[syncStatusIndex]
            let notes = makeNotes(projectIndex: projectIndex, scanIndex: scanNumber)

            return RoomScanSummary(
                id: scanID,
                name: roomNames[index],
                createdAt: createdAt,
                thumbnailName: thumbnailName,
                syncStatus: syncStatus,
                notes: notes
            )
        }
    }

    private nonisolated static func makeNotes(projectIndex: Int, scanIndex: Int) -> [RoomScanNoteSummary] {
        let count = (projectIndex + scanIndex) % 3
        guard count > 0 else { return [] }

        let baseDate = fixtureBaseDate
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
