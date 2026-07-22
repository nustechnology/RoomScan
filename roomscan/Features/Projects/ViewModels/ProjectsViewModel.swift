//
//  ProjectsViewModel.swift
//  roomscan
//

import Foundation
import Observation

@MainActor
@Observable
final class ProjectsViewModel {
    static let pageSize = 5

    enum ViewState: Equatable {
        case idle
        case loading
        case loaded
        case empty
    }

    private let service: any ProjectsService
    private var currentPage = 0

    private(set) var viewState: ViewState = .idle
    private(set) var projects: [ProjectSummary] = []
    private(set) var isRefreshing = false
    private(set) var isLoadingNextPage = false
    private(set) var hasMoreProjects = false
    private(set) var showsPaginationError = false
    private(set) var expandedProjectIDs: Set<ProjectSummary.ID> = []

    init(service: any ProjectsService) {
        self.service = service
    }

    func loadInitialProjects() async {
        guard viewState == .idle else { return }
        await reloadProjects(collapseExpanded: false)
    }

    func refreshProjects() async {
        await reloadProjects(collapseExpanded: true)
    }

    func loadNextPageIfNeeded(currentProjectID: ProjectSummary.ID) async {
        guard currentProjectID == projects.last?.id else { return }
        guard hasMoreProjects, !isLoadingNextPage, viewState == .loaded else { return }

        await loadPage(currentPage + 1)
    }

    func retryPagination() async {
        guard showsPaginationError else { return }
        showsPaginationError = false
        await loadPage(currentPage + 1)
    }

    func toggleExpansion(for projectID: ProjectSummary.ID) {
        if expandedProjectIDs.contains(projectID) {
            expandedProjectIDs.remove(projectID)
        } else {
            expandedProjectIDs.insert(projectID)
        }
    }

    func isExpanded(_ projectID: ProjectSummary.ID) -> Bool {
        expandedProjectIDs.contains(projectID)
    }

    func visibleRoomScans(for project: ProjectSummary) -> [RoomScanSummary] {
        guard !isExpanded(project.id) else { return project.roomScans }
        return Array(project.roomScans.prefix(3))
    }

    func showsExpandControl(for project: ProjectSummary) -> Bool {
        project.roomScans.count > 3
    }

    private func reloadProjects(collapseExpanded: Bool) async {
        let hasLoadedProjects = !projects.isEmpty
        if hasLoadedProjects {
            isRefreshing = true
        } else {
            viewState = .loading
        }
        showsPaginationError = false

        if collapseExpanded {
            expandedProjectIDs.removeAll()
        }

        do {
            let page = try await service.fetchProjects(page: 1, pageSize: Self.pageSize)
            currentPage = 1
            projects = page.projects
            hasMoreProjects = page.hasMore
            viewState = page.projects.isEmpty ? .empty : .loaded
        } catch {
            projects = []
            hasMoreProjects = false
            viewState = .empty
        }

        isRefreshing = false
    }

    private func loadPage(_ page: Int) async {
        isLoadingNextPage = true
        showsPaginationError = false

        do {
            let projectPage = try await service.fetchProjects(page: page, pageSize: Self.pageSize)
            appendUnique(projectPage.projects)
            currentPage = page
            hasMoreProjects = projectPage.hasMore
        } catch {
            showsPaginationError = true
        }

        isLoadingNextPage = false
    }

    private func appendUnique(_ newProjects: [ProjectSummary]) {
        let existingIDs = Set(projects.map(\.id))
        projects.append(contentsOf: newProjects.filter { !existingIDs.contains($0.id) })
    }
}
