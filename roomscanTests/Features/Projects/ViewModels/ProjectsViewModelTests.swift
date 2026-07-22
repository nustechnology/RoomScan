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

    @Test func initialLoadSortsProjectsByUpdatedAtDescending() async {
        let projects = makeProjects(count: 8).shuffled()
        let service = TestProjectsService(projects: projects)
        let viewModel = ProjectsViewModel(service: service)

        await viewModel.loadInitialProjects()

        #expect(viewModel.projects.map(\.id) == ["project-1", "project-2", "project-3", "project-4", "project-5"])
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
            updatedAt: Date(timeIntervalSince1970: TimeInterval(10_000 - index)),
            roomScans: (1...scanCount).map {
                RoomScanSummary(
                    id: "project-\(index)-scan-\($0)",
                    name: "Room \($0)",
                    createdAt: Date(timeIntervalSince1970: TimeInterval(1_000 - $0)),
                    thumbnailName: "thumbnail-\($0)",
                    syncStatus: .synced,
                    notes: []
                )
            }
        )
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

    init(projects: [ProjectSummary], failingPages: Set<Int> = []) {
        self.sortedProjects = projects.sorted { $0.updatedAt > $1.updatedAt }
        self.failingPages = failingPages
    }

    func fetchProjects(page: Int, pageSize: Int) async throws -> ProjectPage {
        requests.append(PageRequest(page: page, pageSize: pageSize))

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
}
