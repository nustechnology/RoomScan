//
//  MockProjectsService.swift
//  roomscan
//

import Foundation

actor MockProjectsService: ProjectsLocalCache {
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

    func fetchProject(id: String) async throws -> ProjectSummary {
        try await simulateDelay()
        guard let project = sourceProjectsForScenario().first(where: { $0.id == id }) else {
            throw ProjectsServiceError.projectNotFound
        }
        return project
    }

    func updateProject(id: String, name: String, description: String, revision: Int = 1) async throws -> ProjectSummary {
        try await simulateDelay()

        guard let index = projects.firstIndex(where: { $0.id == id }) else {
            throw ProjectsServiceError.projectNotFound
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
            roomScans: existing.roomScans,
            scanCount: existing.scanCount
        )
        projects[index] = updated
        projects.sort { $0.updatedAt > $1.updatedAt }
        return updated
    }

    func deleteProject(id: String) async throws {
        try await simulateDelay()

        guard projects.contains(where: { $0.id == id }) else {
            throw ProjectsServiceError.projectNotFound
        }

        projects.removeAll { $0.id == id }
    }

    func fetchAllProjectsSortedByUpdated() async throws -> [ProjectSummary] {
        try await simulateDelay()
        if case .failPage = scenario {
            throw ProjectsServiceError.network
        }
        return sourceProjectsForScenario().sorted { $0.updatedAt > $1.updatedAt }
    }

    func createProject(name: String, projectDescription: String) async throws -> ProjectSummary {
        try await simulateDelay()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = projectDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 50 else {
            throw ProjectsServiceError.invalidProjectName
        }
        guard trimmedDescription.count <= 500 else {
            throw ProjectsServiceError.invalidProjectName
        }

        let newProject = ProjectSummary(
            id: UUID().uuidString,
            name: trimmed,
            ownerName: "You",
            createdAt: Date(),
            updatedAt: Date(),
            description: trimmedDescription,
            sharedUserCount: 0,
            roomScans: []
        )
        projects.insert(newProject, at: 0)
        return newProject
    }

    func cacheProject(_ project: ProjectSummary) throws {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = ProjectSummary.mergingRemoteCache(project, over: projects[index])
        } else {
            projects.insert(project, at: 0)
        }
        projects.sort { $0.updatedAt > $1.updatedAt }
    }

    func replaceCachedProject(_ project: ProjectSummary) throws {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.insert(project, at: 0)
        }
        projects.sort { $0.updatedAt > $1.updatedAt }
    }

    func isScanNameDuplicate(name: String, projectID: String) async throws -> Bool {
        try await simulateDelay()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let project = projects.first(where: { $0.id == projectID }) else {
            return false
        }
        return project.roomScans.contains { $0.name.lowercased() == trimmed.lowercased() }
    }

    func saveScan(draft: RoomScanDraft, name: String, projectID: String, meshURL: URL) async throws -> RoomScanSummary {
        try await simulateDelay()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName.count <= 50 else {
            throw ProjectsServiceError.invalidScanName
        }

        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            throw ProjectsServiceError.projectNotFound
        }

        let isDuplicate = projects[projectIndex].roomScans.contains {
            $0.name.lowercased() == trimmedName.lowercased()
        }
        if isDuplicate {
            throw ProjectsServiceError.duplicateScanName
        }

        let newScan = RoomScanSummary(
            id: draft.id,
            name: trimmedName,
            createdAt: draft.createdAt,
            localModelURL: meshURL,
            thumbnailName: "thumbnail-0",
            syncStatus: .pending,
            notes: []
        )

        var updatedScans = projects[projectIndex].roomScans
        updatedScans.insert(newScan, at: 0)

        projects[projectIndex] = projects[projectIndex].withRoomScans(
            updatedScans,
            scanCountDelta: 1
        )
        projects.sort { $0.updatedAt > $1.updatedAt }

        return newScan
    }

    func renameScan(projectID: String, scanID: String, name: String) async throws -> RoomScanSummary {
        try await simulateDelay()

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName.count <= 100 else {
            throw ProjectsServiceError.invalidScanName
        }

        let (projectIndex, scanIndex) = try indices(projectID: projectID, scanID: scanID)
        let project = projects[projectIndex]
        let existing = project.roomScans[scanIndex]
        let updatedScan = RoomScanSummary(
            id: existing.id,
            name: trimmedName,
            createdAt: existing.createdAt,
            localModelURL: existing.localModelURL,
            thumbnailName: existing.thumbnailName,
            syncStatus: existing.syncStatus,
            creatorUserID: existing.creatorUserID,
            creatorDisplayName: existing.creatorDisplayName,
            notes: existing.notes,
            noteCount: existing.noteCount
        )
        guard let updatedProject = project.replacingScan(updatedScan) else {
            throw ProjectsServiceError.notFound
        }
        projects[projectIndex] = updatedProject
        projects.sort { $0.updatedAt > $1.updatedAt }
        return updatedScan
    }

    func deleteScan(projectID: String, scanID: String) async throws {
        try await simulateDelay()

        let (projectIndex, _) = try indices(projectID: projectID, scanID: scanID)
        let project = projects[projectIndex]
        projects[projectIndex] = project.removingScan(id: scanID)
        projects.sort { $0.updatedAt > $1.updatedAt }
    }

    func retryScanUpload(projectID: String, scanID: String) async throws -> RoomScanSummary {
        try await simulateDelay()

        let (projectIndex, scanIndex) = try indices(projectID: projectID, scanID: scanID)
        let project = projects[projectIndex]
        let existing = project.roomScans[scanIndex]
        let updatedScan = RoomScanSummary(
            id: existing.id,
            name: existing.name,
            createdAt: existing.createdAt,
            localModelURL: existing.localModelURL,
            thumbnailName: existing.thumbnailName,
            syncStatus: .synced,
            creatorUserID: existing.creatorUserID,
            creatorDisplayName: existing.creatorDisplayName,
            notes: existing.notes,
            noteCount: existing.noteCount
        )
        guard let updatedProject = project.replacingScan(updatedScan) else {
            throw ProjectsServiceError.notFound
        }
        projects[projectIndex] = updatedProject
        projects.sort { $0.updatedAt > $1.updatedAt }
        return updatedScan
    }

    private func indices(projectID: String, scanID: String) throws -> (Int, Int) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            throw ProjectsServiceError.projectNotFound
        }
        guard let scanIndex = projects[projectIndex].roomScans.firstIndex(where: { $0.id == scanID }) else {
            throw ProjectsServiceError.notFound
        }
        return (projectIndex, scanIndex)
    }

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

    private func simulateDelay() async throws {
        guard simulatedDelayNanoseconds > 0 else { return }
        try await Task.sleep(nanoseconds: simulatedDelayNanoseconds)
    }
}
