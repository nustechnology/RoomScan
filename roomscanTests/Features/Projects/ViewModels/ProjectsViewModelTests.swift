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
                thumbnailName: "thumbnail-\($0)",
                syncStatus: .synced,
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
    private let sortedProjects: [ProjectSummary]
    private var failingPages: Set<Int>
    private var delayedPages: [Int: UInt64]

    init(
        projects: [ProjectSummary],
        failingPages: Set<Int> = [],
        delayedPages: [Int: UInt64] = [:],
        preservesProjectOrder: Bool = false
    ) {
        self.sortedProjects = preservesProjectOrder
            ? projects
            : projects.sorted { $0.updatedAt > $1.updatedAt }
        self.failingPages = failingPages
        self.delayedPages = delayedPages
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
        guard startIndex < sortedProjects.count else {
            return ProjectPage(projects: [], hasMore: false)
        }

        let endIndex = min(startIndex + pageSize, sortedProjects.count)
        return ProjectPage(
            projects: Array(sortedProjects[startIndex..<endIndex]),
            hasMore: endIndex < sortedProjects.count
        )
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
