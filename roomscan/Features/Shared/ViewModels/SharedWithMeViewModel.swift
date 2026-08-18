//
//  SharedWithMeViewModel.swift
//  roomscan
//

import Foundation
import Observation

@MainActor
@Observable
final class SharedWithMeViewModel {
    enum SubTab: Hashable, CaseIterable {
        case projects
        case scans
    }

    enum ViewState: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case failed
    }

    enum PendingAlert: Equatable {
        case inactiveTap(scope: SharedItemScope, id: String, status: SharedAccessStatus)
        case confirmRemove(scope: SharedItemScope, id: String)
    }

    private let service: any SharedService
    private let ingestQueue: PendingAcceptedSharedIngestQueue
    private var projectsRequestGeneration = 0
    private var scansRequestGeneration = 0

    private(set) var selectedSubTab: SubTab = .projects
    private(set) var projectsViewState: ViewState = .idle
    private(set) var scansViewState: ViewState = .idle
    private(set) var projects: [SharedProjectItem] = []
    private(set) var scans: [SharedScanItem] = []
    private(set) var toastMessage: String?
    private(set) var pendingAlert: PendingAlert?
    private(set) var isRemovingItem = false

    init(service: any SharedService) {
        self.service = service
        self.ingestQueue = PendingAcceptedSharedIngestQueue(service: service)
    }

    func selectSubTab(_ tab: SubTab) {
        selectedSubTab = tab
    }

    func loadInitialContent() async {
        async let projectsLoad: Void = loadProjectsIfNeeded()
        async let scansLoad: Void = loadScansIfNeeded()
        _ = await (projectsLoad, scansLoad)
    }

    /// Upserts an accepted invitation into Shared With Me. Failures are retained and
    /// retried on the next Shared With Me refresh.
    func ingestAcceptedDestination(_ destination: AcceptedInvitationDestination) async {
        _ = await ingestQueue.ingest(destination)
    }

    func refreshSelectedTab() async {
        await ingestQueue.retryPending()
        switch selectedSubTab {
        case .projects:
            await reloadProjects()
        case .scans:
            await reloadScans()
        }
    }

    func refreshAllContent() async {
        await ingestQueue.retryPending()
        async let projectsReload: Void = reloadProjects()
        async let scansReload: Void = reloadScans()
        _ = await (projectsReload, scansReload)
    }

    func retrySelectedTab() async {
        await refreshSelectedTab()
    }

    func handleItemTap(scope: SharedItemScope, id: String) -> SharedItemTapResult? {
        switch scope {
        case .project:
            guard let project = projects.first(where: { $0.id == id }) else { return nil }
            if project.status.isActive {
                guard let detail = project.detailProject else { return nil }
                return .openProject(detail)
            }
            pendingAlert = .inactiveTap(scope: .project, id: id, status: project.status)
            return nil

        case .scan:
            guard let scan = scans.first(where: { $0.id == id }) else { return nil }
            if scan.status.isActive {
                guard let detail = scan.detailScan else { return nil }
                return .openScan(projectID: scan.projectID, scan: detail)
            }
            pendingAlert = .inactiveTap(scope: .scan, id: id, status: scan.status)
            return nil
        }
    }

    func requestRemove(scope: SharedItemScope, id: String) {
        guard !isRemovingItem else { return }
        pendingAlert = .confirmRemove(scope: scope, id: id)
    }

    func dismissAlert() {
        pendingAlert = nil
    }

    func confirmPendingAlertAction() async {
        guard !isRemovingItem, let pendingAlert else { return }
        let scope: SharedItemScope
        let id: String

        switch pendingAlert {
        case .inactiveTap(let itemScope, let itemID, _):
            scope = itemScope
            id = itemID
        case .confirmRemove(let itemScope, let itemID):
            scope = itemScope
            id = itemID
        }

        self.pendingAlert = nil
        await removeItem(id: id, scope: scope)
    }

    func dismissToast() {
        toastMessage = nil
    }

    private func loadProjectsIfNeeded() async {
        guard projectsViewState == .idle else { return }
        await reloadProjects()
    }

    private func loadScansIfNeeded() async {
        guard scansViewState == .idle else { return }
        await reloadScans()
    }

    private func reloadProjects() async {
        projectsRequestGeneration += 1
        let generation = projectsRequestGeneration
        projectsViewState = projects.isEmpty ? .loading : projectsViewState

        do {
            let fetched = try await service.fetchSharedProjects()
            guard generation == projectsRequestGeneration else { return }
            projects = fetched
            projectsViewState = fetched.isEmpty ? .empty : .loaded
        } catch {
            guard generation == projectsRequestGeneration else { return }
            if projects.isEmpty {
                projectsViewState = .failed
            } else {
                toastMessage = String(localized: "shared.action.error")
            }
        }
    }

    private func reloadScans() async {
        scansRequestGeneration += 1
        let generation = scansRequestGeneration
        scansViewState = scans.isEmpty ? .loading : scansViewState

        do {
            let fetched = try await service.fetchSharedScans()
            guard generation == scansRequestGeneration else { return }
            scans = fetched
            scansViewState = fetched.isEmpty ? .empty : .loaded
        } catch {
            guard generation == scansRequestGeneration else { return }
            if scans.isEmpty {
                scansViewState = .failed
            } else {
                toastMessage = String(localized: "shared.action.error")
            }
        }
    }

    private func removeItem(id: String, scope: SharedItemScope) async {
        guard !isRemovingItem else { return }
        isRemovingItem = true
        defer { isRemovingItem = false }

        do {
            try await service.removeSharedItem(id: id, scope: scope)
            switch scope {
            case .project:
                projects.removeAll { $0.id == id }
                projectsViewState = projects.isEmpty ? .empty : .loaded
            case .scan:
                scans.removeAll { $0.id == id }
                scansViewState = scans.isEmpty ? .empty : .loaded
            }
            toastMessage = String(localized: "shared.remove.toast")
        } catch {
            toastMessage = String(localized: "shared.action.error")
        }
    }
}

enum SharedItemTapResult: Equatable {
    case openProject(ProjectSummary)
    case openScan(projectID: String, scan: RoomScanSummary)
}

extension SharedWithMeViewModel.SubTab {
    var localizedTitle: String {
        switch self {
        case .projects:
            return String(localized: "shared.subtab.projects")
        case .scans:
            return String(localized: "shared.subtab.scans")
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .projects:
            return "shared.subtab.projects"
        case .scans:
            return "shared.subtab.scans"
        }
    }
}
