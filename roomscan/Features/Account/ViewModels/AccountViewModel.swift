//
//  AccountViewModel.swift
//  roomscan
//

import Foundation
import Observation

@MainActor
@Observable
final class AccountViewModel {
    private let projectsService: any ProjectsService
    private let sharedService: any SharedService
    private let storageMeasuring: any AccountStorageMeasuring

    private(set) var metrics: AccountMetrics?
    private(set) var isLoading = false
    private(set) var loadFailed = false
    private(set) var showsSignOutConfirmation = false

    private var loadGeneration = 0

    init(
        projectsService: any ProjectsService,
        sharedService: any SharedService,
        storageMeasuring: any AccountStorageMeasuring = MockAccountStorageMeasuring()
    ) {
        self.projectsService = projectsService
        self.sharedService = sharedService
        self.storageMeasuring = storageMeasuring
    }

    func loadMetrics() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = metrics == nil

        do {
            async let projectsTask = fetchAllProjects()
            async let sharedProjectsTask = sharedService.fetchSharedProjects()
            async let storageTask = storageMeasuring.usedBytes()

            let projects = try await projectsTask
            let sharedProjects = try await sharedProjectsTask
            let storageUsedBytes = await storageTask

            guard generation == loadGeneration else { return }

            let allScans = projects.flatMap(\.roomScans)
            metrics = AccountMetrics(
                localScanCount: allScans.count,
                pendingSyncCount: allScans.filter { $0.syncStatus != .synced }.count,
                sharedProjectCount: sharedProjects.count,
                storageUsedBytes: storageUsedBytes
            )
            loadFailed = false
            isLoading = false
        } catch {
            guard generation == loadGeneration else { return }
            loadFailed = true
            isLoading = false
        }
    }

    func requestSignOut() {
        showsSignOutConfirmation = true
    }

    func dismissSignOutConfirmation() {
        showsSignOutConfirmation = false
    }

    func confirmSignOut(onSignOut: () -> Void) {
        showsSignOutConfirmation = false
        onSignOut()
    }

    private func fetchAllProjects() async throws -> [ProjectSummary] {
        var allProjects: [ProjectSummary] = []
        var page = 1
        let pageSize = 50

        while true {
            let result = try await projectsService.fetchProjects(page: page, pageSize: pageSize)
            allProjects.append(contentsOf: result.projects)
            if !result.hasMore || result.projects.isEmpty {
                break
            }
            page += 1
        }

        return allProjects
    }
}
