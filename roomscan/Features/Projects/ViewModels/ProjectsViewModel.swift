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
        case failed
    }

    private let service: any ProjectsService
    private var currentPage = 0
    private var requestGeneration = 0

    private(set) var viewState: ViewState = .idle
    private(set) var projects: [ProjectSummary] = []
    private(set) var isRefreshing = false
    private(set) var isLoadingNextPage = false
    private(set) var hasMoreProjects = false
    private(set) var showsPaginationError = false
    private(set) var showsDeleteSuccessToast = false
    private(set) var showsActionErrorToast = false
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
        guard hasMoreProjects, !isRefreshing, !isLoadingNextPage, viewState == .loaded else { return }

        await loadPage(currentPage + 1)
    }

    func retryPagination() async {
        guard showsPaginationError else { return }
        guard !isRefreshing, !isLoadingNextPage else { return }
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

    @discardableResult
    func updateProject(id: ProjectSummary.ID, name: String, description: String) async -> Bool {
        do {
            let updated = try await service.updateProject(id: id, name: name, description: description)
            if let index = projects.firstIndex(where: { $0.id == id }) {
                projects[index] = updated
                projects.sort { $0.updatedAt > $1.updatedAt }
            }
            showsActionErrorToast = false
            return true
        } catch {
            showsActionErrorToast = true
            return false
        }
    }

    @discardableResult
    func deleteProject(id: ProjectSummary.ID) async -> Bool {
        do {
            try await service.deleteProject(id: id)
            projects.removeAll { $0.id == id }
            expandedProjectIDs.remove(id)
            if projects.isEmpty {
                if hasMoreProjects {
                    await reloadProjects(collapseExpanded: false)
                } else {
                    hasMoreProjects = false
                    viewState = .empty
                }
            }
            showsActionErrorToast = false
            showsDeleteSuccessToast = true
            return true
        } catch {
            showsDeleteSuccessToast = false
            showsActionErrorToast = true
            return false
        }
    }

    func dismissDeleteSuccessToast() {
        showsDeleteSuccessToast = false
    }

    func dismissActionErrorToast() {
        showsActionErrorToast = false
    }

    private func reloadProjects(collapseExpanded: Bool) async {
        requestGeneration += 1
        let generation = requestGeneration
        defer {
            if generation == requestGeneration {
                isRefreshing = false
            }
        }
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
            guard generation == requestGeneration else { return }
            currentPage = 1
            projects = page.projects
            hasMoreProjects = page.hasMore
            viewState = page.projects.isEmpty ? .empty : .loaded
        } catch {
            guard generation == requestGeneration else { return }
            if hasLoadedProjects {
                showsPaginationError = true
                viewState = .loaded
            } else {
                projects = []
                hasMoreProjects = false
                viewState = .failed
            }
        }

    }

    private func loadPage(_ page: Int) async {
        let generation = requestGeneration
        isLoadingNextPage = true
        defer {
            isLoadingNextPage = false
        }
        showsPaginationError = false

        do {
            let projectPage = try await service.fetchProjects(page: page, pageSize: Self.pageSize)
            guard generation == requestGeneration else { return }
            appendUnique(projectPage.projects)
            currentPage = page
            hasMoreProjects = projectPage.hasMore
        } catch {
            guard generation == requestGeneration else { return }
            showsPaginationError = true
        }

    }

    private func appendUnique(_ newProjects: [ProjectSummary]) {
        let existingIDs = Set(projects.map(\.id))
        projects.append(contentsOf: newProjects.filter { !existingIDs.contains($0.id) })
    }
}
