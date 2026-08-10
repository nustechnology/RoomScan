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

struct VisibleProject: Identifiable, Equatable {
        let project: ProjectSummary
        let roomScans: [RoomScanSummary]
        let showsAllRoomScans: Bool

        var id: ProjectSummary.ID { project.id }
    }

    private let service: any ProjectsService
    private var currentPage = 0
    private var requestGeneration = 0
    private var allProjects: [ProjectSummary] = []
    private var hasLoadedCompleteDataset = false
    private var searchLoadingTask: Task<Void, Never>?

    private(set) var viewState: ViewState = .idle
    private(set) var projects: [ProjectSummary] = []
    private(set) var isRefreshing = false
    private(set) var isLoadingNextPage = false
    private(set) var hasMoreProjects = false
    private(set) var showsPaginationError = false
    private(set) var showsDeleteSuccessToast = false
    private(set) var showsActionErrorToast = false
    private(set) var isDeletingProject = false
    private(set) var expandedProjectIDs: Set<ProjectSummary.ID> = []
    private(set) var searchQuery = ""

    init(service: any ProjectsService) {
        self.service = service
    }

    var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasActiveSearch: Bool {
        !trimmedSearchQuery.isEmpty
    }

    var visibleProjects: [VisibleProject] {
        if hasActiveSearch {
            return filteredProjects(matching: trimmedSearchQuery)
        }

        return projects.map {
            VisibleProject(
                project: $0,
                roomScans: visibleRoomScans(for: $0),
                showsAllRoomScans: isExpanded($0.id)
            )
        }
    }

    var showsSearchEmptyState: Bool {
        viewState == .loaded && hasActiveSearch && visibleProjects.isEmpty
    }

    func loadInitialProjects() async {
        guard viewState == .idle else { return }
        await reloadProjects(collapseExpanded: false)
    }

    func refreshProjects() async {
        await reloadProjects(collapseExpanded: true)
    }

    func loadNextPageIfNeeded(currentProjectID: ProjectSummary.ID) async {
        guard !hasActiveSearch else { return }
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
            requestGeneration += 1
            if let index = projects.firstIndex(where: { $0.id == id }) {
                projects[index] = updated
                projects.sort { $0.updatedAt > $1.updatedAt }
            }
            replaceProjectInAllProjects(updated)
            showsActionErrorToast = false
            return true
        } catch {
            showsActionErrorToast = true
            return false
        }
    }

    @discardableResult
    func deleteProject(id: ProjectSummary.ID) async -> Bool {
        guard !isDeletingProject else { return false }
        isDeletingProject = true
        defer { isDeletingProject = false }

        do {
            try await service.deleteProject(id: id)
            requestGeneration += 1
            projects.removeAll { $0.id == id }
            allProjects.removeAll { $0.id == id }
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

    func applyUpdatedScan(projectID: ProjectSummary.ID, scan: RoomScanSummary) {
        projects = updatedProjectsByApplyingScanUpdate(
            to: projects,
            projectID: projectID,
            scan: scan
        )
        allProjects = updatedProjectsByApplyingScanUpdate(
            to: allProjects,
            projectID: projectID,
            scan: scan
        )
        projects.sort { $0.updatedAt > $1.updatedAt }
        allProjects.sort { $0.updatedAt > $1.updatedAt }
    }

    func applyDeletedScan(projectID: ProjectSummary.ID, scanID: RoomScanSummary.ID) {
        projects = updatedProjectsByApplyingScanDeletion(
            to: projects,
            projectID: projectID,
            scanID: scanID
        )
        allProjects = updatedProjectsByApplyingScanDeletion(
            to: allProjects,
            projectID: projectID,
            scanID: scanID
        )
        projects.sort { $0.updatedAt > $1.updatedAt }
        allProjects.sort { $0.updatedAt > $1.updatedAt }
    }

    func prependCreatedProject(_ project: ProjectSummary) {
        projects.removeAll { $0.id == project.id }
        allProjects.removeAll { $0.id == project.id }
        projects.insert(project, at: 0)
        allProjects.insert(project, at: 0)
        projects.sort { $0.updatedAt > $1.updatedAt }
        allProjects.sort { $0.updatedAt > $1.updatedAt }
        if !projects.isEmpty {
            viewState = .loaded
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
        searchLoadingTask?.cancel()
        searchLoadingTask = nil
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
            allProjects = page.projects
            hasLoadedCompleteDataset = !page.hasMore
            hasMoreProjects = page.hasMore
            viewState = page.projects.isEmpty ? .empty : .loaded
            if hasActiveSearch {
                await ensureCompleteDatasetLoadedForSearch()
            }
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
            hasLoadedCompleteDataset = !projectPage.hasMore
        } catch {
            guard generation == requestGeneration else { return }
            showsPaginationError = true
        }

    }

    private func appendUnique(_ newProjects: [ProjectSummary]) {
        let existingIDs = Set(projects.map(\.id))
        projects.append(contentsOf: newProjects.filter { !existingIDs.contains($0.id) })
        mergeIntoAllProjects(newProjects)
    }

    private func ensureCompleteDatasetLoadedForSearch() async {
        if let searchLoadingTask, !searchLoadingTask.isCancelled {
            await searchLoadingTask.value
            self.searchLoadingTask = nil
        }

        guard !hasLoadedCompleteDataset else { return }
        guard searchLoadingTask == nil else { return }

        searchLoadingTask = Task { [weak self] in
            guard let self else { return }
            await self.loadCompleteDatasetForSearch()
            guard !Task.isCancelled else { return }
            self.searchLoadingTask = nil
        }

        await searchLoadingTask?.value
    }

    private func loadCompleteDatasetForSearch() async {
        let generation = requestGeneration
        var page = currentPage > 0 ? currentPage + 1 : 1
        var loadedProjects: [ProjectSummary] = []
        var hasMore = currentPage > 0 ? hasMoreProjects : true

        while hasMore {
            do {
                try Task.checkCancellation()
                let result = try await service.fetchProjects(page: page, pageSize: Self.pageSize)
                try Task.checkCancellation()
                loadedProjects.append(contentsOf: result.projects)
                hasMore = result.hasMore
                page += 1
            } catch {
                return
            }
        }

        guard generation == requestGeneration else { return }
        guard !Task.isCancelled else { return }
        mergeIntoAllProjects(loadedProjects)
        hasLoadedCompleteDataset = true
    }
}

extension ProjectsViewModel {
    func updateSearchQuery(_ query: String) {
        searchQuery = query

        guard hasActiveSearch else {
            searchLoadingTask?.cancel()
            searchLoadingTask = nil
            return
        }

        guard !hasLoadedCompleteDataset else { return }
        guard searchLoadingTask == nil else { return }

        searchLoadingTask = Task { [weak self] in
            guard let self else { return }
            await self.loadCompleteDatasetForSearch()
            guard !Task.isCancelled else { return }
            self.searchLoadingTask = nil
        }
    }

    func waitForSearchLoading() async {
        await searchLoadingTask?.value
    }
}

private extension ProjectsViewModel {
    func filteredProjects(matching query: String) -> [VisibleProject] {
        let normalizedQuery = query.localizedLowercase

        return allProjects.compactMap { project in
            let projectMatches = project.name.localizedLowercase.contains(normalizedQuery)
            if projectMatches {
                return VisibleProject(
                    project: project,
                    roomScans: project.roomScans,
                    showsAllRoomScans: true
                )
            }

            let matchingRoomScans = project.roomScans.filter {
                $0.name.localizedLowercase.contains(normalizedQuery)
            }

            guard !matchingRoomScans.isEmpty else { return nil }
            return VisibleProject(
                project: project,
                roomScans: matchingRoomScans,
                showsAllRoomScans: false
            )
        }
    }

    func mergeIntoAllProjects(_ newProjects: [ProjectSummary]) {
        guard !newProjects.isEmpty else { return }

        let newProjectsByID = Dictionary(uniqueKeysWithValues: newProjects.map { ($0.id, $0) })
        allProjects = allProjects.map { newProjectsByID[$0.id] ?? $0 }

        let existingIDs = Set(allProjects.map(\.id))
        allProjects.append(contentsOf: newProjects.filter { !existingIDs.contains($0.id) })
    }

    func replaceProjectInAllProjects(_ updated: ProjectSummary) {
        guard let index = allProjects.firstIndex(where: { $0.id == updated.id }) else { return }
        allProjects[index] = updated
        allProjects.sort { $0.updatedAt > $1.updatedAt }
    }

    func updatedProjectsByApplyingScanUpdate(
        to source: [ProjectSummary],
        projectID: ProjectSummary.ID,
        scan: RoomScanSummary
    ) -> [ProjectSummary] {
        guard let projectIndex = source.firstIndex(where: { $0.id == projectID }) else { return source }
        let project = source[projectIndex]
        guard let updatedProject = project.replacingScan(scan) else { return source }

        var updatedProjects = source
        updatedProjects[projectIndex] = updatedProject
        return updatedProjects
    }

    func updatedProjectsByApplyingScanDeletion(
        to source: [ProjectSummary],
        projectID: ProjectSummary.ID,
        scanID: RoomScanSummary.ID
    ) -> [ProjectSummary] {
        guard let projectIndex = source.firstIndex(where: { $0.id == projectID }) else { return source }
        let project = source[projectIndex]
        guard project.roomScans.contains(where: { $0.id == scanID }) else { return source }

        var updatedProjects = source
        updatedProjects[projectIndex] = project.removingScan(id: scanID)
        return updatedProjects
    }
}
