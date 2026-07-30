//
//  ProjectsViewModelTests.swift
//  roomscanTests
//

import Foundation
import Testing
@testable import roomscan

@MainActor
struct ProjectsViewModelTests {
    @Test func initialLoadFetchesExactlyFiveProjects() async {
        let service = TestProjectsService(projects: makeProjects(count: 12))
        let viewModel = ProjectsViewModel(service: service)

        await viewModel.loadInitialProjects()

        #expect(viewModel.projects.count == 5)
        #expect(await service.requests == [PageRequest(page: 1, pageSize: 5)])
    }

    @Test func initialLoadUsesServiceProjectOrder() async {
        let projects = [3, 1, 5, 2, 4, 6, 8, 7].map {
            makeProject(index: $0, scanCount: 5)
        }
        let service = TestProjectsService(projects: projects, preservesProjectOrder: true)
        let viewModel = ProjectsViewModel(service: service)

        await viewModel.loadInitialProjects()

        #expect(viewModel.projects.map(\.id) == ["project-3", "project-1", "project-5", "project-2", "project-4"])
    }

    @Test func initialLoadPreservesProjectMetadata() async {
        let project = makeProject(index: 1, scanCount: 0)
        let service = TestProjectsService(projects: [project])
        let viewModel = ProjectsViewModel(service: service)

        await viewModel.loadInitialProjects()

        #expect(viewModel.projects.first?.ownerName == "You")
        #expect(viewModel.projects.first?.createdAt == project.createdAt)
        #expect(viewModel.projects.first?.sharedUserCount == 2)
    }

    @Test func lazyLoadingAppendsNextFiveWithoutDuplicates() async {
        let service = TestProjectsService(projects: makeProjects(count: 12))
        let viewModel = ProjectsViewModel(service: service)
        await viewModel.loadInitialProjects()

        await viewModel.loadNextPageIfNeeded(currentProjectID: "project-5")

        #expect(viewModel.projects.count == 10)
        #expect(Set(viewModel.projects.map(\.id)).count == 10)
    }

    @Test func pullToRefreshResetsToFirstPageAndClearsExpandedState() async {
        let service = TestProjectsService(projects: makeProjects(count: 12))
        let viewModel = ProjectsViewModel(service: service)
        await viewModel.loadInitialProjects()
        await viewModel.loadNextPageIfNeeded(currentProjectID: "project-5")
        viewModel.toggleExpansion(for: "project-1")

        await viewModel.refreshProjects()

        #expect(viewModel.projects.map(\.id) == ["project-1", "project-2", "project-3", "project-4", "project-5"])
        #expect(viewModel.expandedProjectIDs.isEmpty)
    }

    @Test func refreshFailurePreservesLoadedProjectsAndExposesError() async {
        let service = TestProjectsService(projects: makeProjects(count: 12))
        let viewModel = ProjectsViewModel(service: service)
        await viewModel.loadInitialProjects()
        await service.setFailingPages([1])

        await viewModel.refreshProjects()

        #expect(viewModel.projects.map(\.id) == ["project-1", "project-2", "project-3", "project-4", "project-5"])
        #expect(viewModel.viewState == .loaded)
        #expect(viewModel.showsPaginationError)
    }

    @Test func initialLoadFailureUsesFailureStateInsteadOfEmpty() async {
        let service = TestProjectsService(projects: makeProjects(count: 12), failingPages: [1])
        let viewModel = ProjectsViewModel(service: service)

        await viewModel.loadInitialProjects()

        #expect(viewModel.projects.isEmpty)
        #expect(viewModel.viewState == .failed)
        #expect(!viewModel.showsPaginationError)
    }

    @Test func stalePaginationResponseAfterRefreshDoesNotAppendOrAdvanceState() async {
        let service = TestProjectsService(
            projects: makeProjects(count: 12),
            delayedPages: [2: 100_000_000]
        )
        let viewModel = ProjectsViewModel(service: service)
        await viewModel.loadInitialProjects()

        let paginationTask = Task {
            await viewModel.loadNextPageIfNeeded(currentProjectID: "project-5")
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        await viewModel.refreshProjects()
        await paginationTask.value

        #expect(viewModel.projects.map(\.id) == ["project-1", "project-2", "project-3", "project-4", "project-5"])
        #expect(viewModel.hasMoreProjects)
        #expect(!viewModel.isLoadingNextPage)
    }

    @Test func paginationIsSkippedWhileRefreshing() async {
        let service = TestProjectsService(projects: makeProjects(count: 12))
        let viewModel = ProjectsViewModel(service: service)
        await viewModel.loadInitialProjects()
        await service.setDelayedPages([1: 100_000_000])

        let refreshTask = Task {
            await viewModel.refreshProjects()
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        await viewModel.loadNextPageIfNeeded(currentProjectID: "project-5")
        await refreshTask.value

        #expect(await service.requests == [
            PageRequest(page: 1, pageSize: 5),
            PageRequest(page: 1, pageSize: 5)
        ])
        #expect(viewModel.projects.count == 5)
    }

    @Test func paginationFailurePreservesLoadedProjectsAndExposesRetryToast() async {
        let service = TestProjectsService(projects: makeProjects(count: 12), failingPages: [2])
        let viewModel = ProjectsViewModel(service: service)
        await viewModel.loadInitialProjects()

        await viewModel.loadNextPageIfNeeded(currentProjectID: "project-5")

        #expect(viewModel.projects.map(\.id) == ["project-1", "project-2", "project-3", "project-4", "project-5"])
        #expect(viewModel.showsPaginationError)
    }

    @Test func retryAfterPaginationFailureFetchesFailedPage() async {
        let service = TestProjectsService(projects: makeProjects(count: 12), failingPages: [2])
        let viewModel = ProjectsViewModel(service: service)
        await viewModel.loadInitialProjects()
        await viewModel.loadNextPageIfNeeded(currentProjectID: "project-5")

        await service.clearFailures()
        await viewModel.retryPagination()

        #expect(viewModel.projects.count == 10)
        #expect(viewModel.projects.last?.id == "project-10")
        #expect(!viewModel.showsPaginationError)
    }

    @Test func expansionShowsThreeScansByDefaultAndAllScansAfterExpand() {
        let service = TestProjectsService(projects: [])
        let viewModel = ProjectsViewModel(service: service)
        let project = makeProject(index: 1, scanCount: 5)

        #expect(viewModel.visibleRoomScans(for: project).count == 3)

        viewModel.toggleExpansion(for: project.id)

        #expect(viewModel.visibleRoomScans(for: project).count == 5)
    }

    @Test func expandButtonHiddenForProjectsWithThreeOrFewerScans() {
        let service = TestProjectsService(projects: [])
        let viewModel = ProjectsViewModel(service: service)

        #expect(!viewModel.showsExpandControl(for: makeProject(index: 1, scanCount: 3)))
        #expect(viewModel.showsExpandControl(for: makeProject(index: 2, scanCount: 4)))
    }

    @Test func updateProjectReplacesItemAndSortsByUpdatedAt() async {
        let service = TestProjectsService(projects: makeProjects(count: 5))
        let viewModel = ProjectsViewModel(service: service)
        await viewModel.loadInitialProjects()

        let didUpdate = await viewModel.updateProject(
            id: "project-3",
            name: "Renamed Project",
            description: "Updated description"
        )

        #expect(didUpdate)
        #expect(viewModel.projects.first?.id == "project-3")
        #expect(viewModel.projects.first?.name == "Renamed Project")
        #expect(viewModel.projects.first?.description == "Updated description")
        #expect(await service.updatedProjectIDs == ["project-3"])
    }

    @Test func deleteProjectRemovesItemAndShowsSuccessToast() async {
        let service = TestProjectsService(projects: makeProjects(count: 5))
        let viewModel = ProjectsViewModel(service: service)
        await viewModel.loadInitialProjects()
        viewModel.toggleExpansion(for: "project-2")

        let didDelete = await viewModel.deleteProject(id: "project-2")

        #expect(didDelete)
        #expect(viewModel.projects.map(\.id) == ["project-1", "project-3", "project-4", "project-5"])
        #expect(!viewModel.expandedProjectIDs.contains("project-2"))
        #expect(viewModel.showsDeleteSuccessToast)
        #expect(!viewModel.showsActionErrorToast)
        #expect(await service.deletedProjectIDs == ["project-2"])
    }

    @Test func deleteLastVisibleProjectShowsEmptyState() async {
        let service = TestProjectsService(projects: [makeProject(index: 1, scanCount: 2)])
        let viewModel = ProjectsViewModel(service: service)
        await viewModel.loadInitialProjects()

        let didDelete = await viewModel.deleteProject(id: "project-1")

        #expect(didDelete)
        #expect(viewModel.projects.isEmpty)
        #expect(viewModel.viewState == .empty)
        #expect(viewModel.showsDeleteSuccessToast)
    }

    @Test func deleteLastLoadedProjectReloadsWhenMorePagesRemain() async {
        let service = TestProjectsService(projects: makeProjects(count: 12))
        let viewModel = ProjectsViewModel(service: service)
        await viewModel.loadInitialProjects()

        for id in ["project-1", "project-2", "project-3", "project-4", "project-5"] {
            let didDelete = await viewModel.deleteProject(id: id)
            #expect(didDelete)
        }

        #expect(viewModel.viewState == .loaded)
        #expect(viewModel.projects.map(\.id) == [
            "project-6", "project-7", "project-8", "project-9", "project-10"
        ])
        #expect(viewModel.hasMoreProjects)
        #expect(viewModel.showsDeleteSuccessToast)
    }

    @Test func updateProjectFailureShowsActionError() async {
        let service = TestProjectsService(projects: makeProjects(count: 5), updateFails: true)
        let viewModel = ProjectsViewModel(service: service)
        await viewModel.loadInitialProjects()

        let didUpdate = await viewModel.updateProject(
            id: "project-1",
            name: "Renamed",
            description: "Updated"
        )

        #expect(!didUpdate)
        #expect(viewModel.projects.first?.name == "Project 1")
        #expect(viewModel.showsActionErrorToast)
    }

    @Test func deleteProjectFailureShowsActionError() async {
        let service = TestProjectsService(projects: makeProjects(count: 5), deleteFails: true)
        let viewModel = ProjectsViewModel(service: service)
        await viewModel.loadInitialProjects()

        let didDelete = await viewModel.deleteProject(id: "project-1")

        #expect(!didDelete)
        #expect(viewModel.projects.map(\.id) == [
            "project-1", "project-2", "project-3", "project-4", "project-5"
        ])
        #expect(viewModel.showsActionErrorToast)
        #expect(!viewModel.showsDeleteSuccessToast)
    }

    private func makeProjects(count: Int) -> [ProjectSummary] {
        (1...count).map { makeProject(index: $0, scanCount: 5) }
    }

    private func makeProject(index: Int, scanCount: Int) -> ProjectSummary {
        ProjectSummary(
            id: "project-\(index)",
            name: "Project \(index)",
            ownerName: "You",
            createdAt: Date(timeIntervalSince1970: TimeInterval(20_000 - index)),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(10_000 - index)),
            description: "Description \(index)",
            sharedUserCount: 2,
            roomScans: makeScans(projectIndex: index, count: scanCount)
        )
    }

    private func makeScans(projectIndex: Int, count: Int) -> [RoomScanSummary] {
        guard count > 0 else { return [] }

        return (1...count).map {
            RoomScanSummary(
                id: "project-\(projectIndex)-scan-\($0)",
                name: "Room \($0)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_000 - $0)),
                localModelURL: nil,
                thumbnailName: "thumbnail-\($0)",
                syncStatus: .synced,
                creatorUserID: AuthenticationSession.mockAppleUser.user.id,
                creatorDisplayName: "Mock Apple User",
                notes: []
            )
        }
    }
}

private struct PageRequest: Equatable {
    let page: Int
    let pageSize: Int
}

private actor TestProjectsService: ProjectsService {
    private(set) var requests: [PageRequest] = []
    private(set) var updatedProjectIDs: [String] = []
    private(set) var deletedProjectIDs: [String] = []
    private var projects: [ProjectSummary]
    private var failingPages: Set<Int>
    private var delayedPages: [Int: UInt64]
    private var updateFails: Bool
    private var deleteFails: Bool

    init(
        projects: [ProjectSummary],
        failingPages: Set<Int> = [],
        delayedPages: [Int: UInt64] = [:],
        preservesProjectOrder: Bool = false,
        updateFails: Bool = false,
        deleteFails: Bool = false
    ) {
        self.projects = preservesProjectOrder
            ? projects
            : projects.sorted { $0.updatedAt > $1.updatedAt }
        self.failingPages = failingPages
        self.delayedPages = delayedPages
        self.updateFails = updateFails
        self.deleteFails = deleteFails
    }

    func fetchProjects(page: Int, pageSize: Int) async throws -> ProjectPage {
        requests.append(PageRequest(page: page, pageSize: pageSize))

        if let delay = delayedPages[page] {
            try await Task.sleep(nanoseconds: delay)
        }

        if failingPages.contains(page) {
            throw ProjectsServiceError.network
        }

        let startIndex = max(page - 1, 0) * pageSize
        guard startIndex < projects.count else {
            return ProjectPage(projects: [], hasMore: false)
        }

        let endIndex = min(startIndex + pageSize, projects.count)
        return ProjectPage(
            projects: Array(projects[startIndex..<endIndex]),
            hasMore: endIndex < projects.count
        )
    }

    func updateProject(id: String, name: String, description: String) async throws -> ProjectSummary {
        if updateFails {
            throw ProjectsServiceError.network
        }

        guard let index = projects.firstIndex(where: { $0.id == id }) else {
            throw ProjectsServiceError.notFound
        }

        let existing = projects[index]
        let updated = ProjectSummary(
            id: existing.id,
            name: name,
            ownerName: existing.ownerName,
            createdAt: existing.createdAt,
            updatedAt: Date(timeIntervalSince1970: 20_000),
            description: description,
            sharedUserCount: existing.sharedUserCount,
            roomScans: existing.roomScans
        )
        projects[index] = updated
        projects.sort { $0.updatedAt > $1.updatedAt }
        updatedProjectIDs.append(id)
        return updated
    }

    func deleteProject(id: String) async throws {
        if deleteFails {
            throw ProjectsServiceError.network
        }

        guard projects.contains(where: { $0.id == id }) else {
            throw ProjectsServiceError.notFound
        }

        projects.removeAll { $0.id == id }
        deletedProjectIDs.append(id)
    }

    func renameScan(projectID: String, scanID: String, name: String) async throws -> RoomScanSummary {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ProjectsServiceError.invalidName
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
            notes: existing.notes
        )
        var roomScans = project.roomScans
        roomScans[scanIndex] = updatedScan
        projects[projectIndex] = ProjectSummary(
            id: project.id,
            name: project.name,
            ownerName: project.ownerName,
            createdAt: project.createdAt,
            updatedAt: Date(timeIntervalSince1970: 20_000),
            description: project.description,
            sharedUserCount: project.sharedUserCount,
            roomScans: roomScans
        )
        return updatedScan
    }

    func deleteScan(projectID: String, scanID: String) async throws {
        let (projectIndex, scanIndex) = try indices(projectID: projectID, scanID: scanID)
        let project = projects[projectIndex]
        var roomScans = project.roomScans
        roomScans.remove(at: scanIndex)
        projects[projectIndex] = ProjectSummary(
            id: project.id,
            name: project.name,
            ownerName: project.ownerName,
            createdAt: project.createdAt,
            updatedAt: Date(timeIntervalSince1970: 20_000),
            description: project.description,
            sharedUserCount: project.sharedUserCount,
            roomScans: roomScans
        )
    }

    func retryScanUpload(projectID: String, scanID: String) async throws -> RoomScanSummary {
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
            notes: existing.notes
        )
        var roomScans = project.roomScans
        roomScans[scanIndex] = updatedScan
        projects[projectIndex] = ProjectSummary(
            id: project.id,
            name: project.name,
            ownerName: project.ownerName,
            createdAt: project.createdAt,
            updatedAt: Date(timeIntervalSince1970: 20_000),
            description: project.description,
            sharedUserCount: project.sharedUserCount,
            roomScans: roomScans
        )
        return updatedScan
    }

    private func indices(projectID: String, scanID: String) throws -> (Int, Int) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            throw ProjectsServiceError.notFound
        }
        guard let scanIndex = projects[projectIndex].roomScans.firstIndex(where: { $0.id == scanID }) else {
            throw ProjectsServiceError.notFound
        }
        return (projectIndex, scanIndex)
    }

    func clearFailures() {
        failingPages.removeAll()
    }

    func setFailingPages(_ pages: Set<Int>) {
        failingPages = pages
    }

    func setDelayedPages(_ pages: [Int: UInt64]) {
        delayedPages = pages
    }
}
