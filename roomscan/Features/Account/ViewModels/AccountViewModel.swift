//
//  AccountViewModel.swift
//  roomscan
//

import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class AccountViewModel {
    private let projectsService: any ProjectsService
    private let sharedService: any SharedService
    private let syncService: any SyncService
    private let usersService: any UsersService
    private let scanStorageService: any ScanStorageService
    private let storageMeasuring: any AccountStorageMeasuring
    private let onUserUpdated: (AuthenticatedUser) -> Void

    private(set) var metrics: AccountMetrics?
    private(set) var isLoading = false
    private(set) var loadFailed = false
    private(set) var showsSignOutConfirmation = false

    private(set) var isEditNameSheetPresented = false
    private(set) var editedDisplayName = ""
    private(set) var isSavingDisplayName = false
    private(set) var editValidationMessage: String?
    private(set) var saveErrorMessage: String?

    private(set) var toastStyle: ToastStyle = .success
    private(set) var toastMessage: String?

    private var loadGeneration = 0
    private var profileLoadGeneration = 0
    private var saveGeneration = 0
    private var baselineDisplayName: String?

    init(
        projectsService: any ProjectsService,
        sharedService: any SharedService,
        syncService: any SyncService,
        usersService: any UsersService = MockUsersService(),
        scanStorageService: any ScanStorageService = LocalScanStorageService(),
        storageMeasuring: any AccountStorageMeasuring = MockAccountStorageMeasuring(),
        onUserUpdated: @escaping (AuthenticatedUser) -> Void = { _ in }
    ) {
        self.projectsService = projectsService
        self.sharedService = sharedService
        self.syncService = syncService
        self.usersService = usersService
        self.scanStorageService = scanStorageService
        self.storageMeasuring = storageMeasuring
        self.onUserUpdated = onUserUpdated
    }

    var canSaveDisplayName: Bool {
        let trimmed = editedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let baseline = baselineDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed != baseline && !isSavingDisplayName
    }

    func loadMetrics() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = metrics == nil

        do {
            async let projectsTask = fetchAllProjects()
            async let sharedProjectsTask = sharedService.fetchSharedProjects()
            async let syncStatusTask = fetchPendingSyncCountFromServer()

            let projects = try await projectsTask
            let sharedProjects = try await sharedProjectsTask
            let serverPendingCount = try await syncStatusTask

            guard generation == loadGeneration else { return }

            let allScans = projects.flatMap(\.roomScans)
            let localScanIDs = await scanStorageService.existingMeshScanIDs(in: allScans.map(\.id))

            guard generation == loadGeneration else { return }

            let storageUsedBytes = await storageMeasuring.usedBytes(forScanIDs: Array(localScanIDs))

            guard generation == loadGeneration else { return }

            let localPendingCount = allScans.filter(\.contributesToLocalUnresolvedCount).count
            let pendingSyncCount: Int
            if let serverPendingCount {
                pendingSyncCount = max(serverPendingCount, localPendingCount)
            } else {
                pendingSyncCount = localPendingCount
            }

            metrics = AccountMetrics(
                localScanCount: localScanIDs.count,
                pendingSyncCount: pendingSyncCount,
                sharedProjectCount: sharedProjects.count,
                storageUsedBytes: storageUsedBytes
            )
            loadFailed = false
            isLoading = false
        } catch is CancellationError {
            guard generation == loadGeneration else { return }
            isLoading = false
        } catch {
            guard generation == loadGeneration else { return }
            loadFailed = true
            isLoading = false
        }
    }

    func loadProfile(currentUser: AuthenticatedUser) async {
        profileLoadGeneration += 1
        let generation = profileLoadGeneration

        do {
            let user = try await usersService.fetchMe(fallingBackTo: currentUser)
            guard generation == profileLoadGeneration else { return }
            onUserUpdated(user)
        } catch is CancellationError {
            return
        } catch {
            // Keep local session data if profile refresh fails.
        }
    }

    func openEditNameSheet(currentDisplayName: String?) {
        baselineDisplayName = currentDisplayName
        editedDisplayName = currentDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        editValidationMessage = nil
        saveErrorMessage = nil
        isSavingDisplayName = false
        isEditNameSheetPresented = true
    }

    func closeEditNameSheet() {
        isEditNameSheetPresented = false
        editedDisplayName = ""
        baselineDisplayName = nil
        editValidationMessage = nil
        saveErrorMessage = nil
        isSavingDisplayName = false
    }

    func updateEditedDisplayName(_ value: String) {
        editedDisplayName = value
        if editValidationMessage != nil {
            editValidationMessage = nil
        }
        if saveErrorMessage != nil {
            saveErrorMessage = nil
        }
    }

    func saveDisplayName(currentUser: AuthenticatedUser) async {
        let trimmed = editedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            editValidationMessage = String(localized: "account.editName.validation.empty")
            return
        }

        profileLoadGeneration += 1
        saveGeneration += 1
        let generation = saveGeneration
        isSavingDisplayName = true
        editValidationMessage = nil
        saveErrorMessage = nil

        do {
            let user = try await usersService.updateMe(
                displayName: trimmed,
                fallingBackTo: currentUser
            )
            guard generation == saveGeneration else { return }
            onUserUpdated(user)
            isSavingDisplayName = false
            closeEditNameSheet()
        } catch is CancellationError {
            guard generation == saveGeneration else { return }
            isSavingDisplayName = false
        } catch {
            guard generation == saveGeneration else { return }
            isSavingDisplayName = false
            saveErrorMessage = String(localized: "account.editName.error")
        }
    }

    func copyPublicUserID(_ publicUserID: String) {
        UIPasteboard.general.string = publicUserID
        toastStyle = .success
        toastMessage = String(localized: "account.toast.publicUserIdCopied")
    }

    func dismissToast() {
        toastMessage = nil
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

    /// Prefer backend `/sync/status` totals; returns `nil` so callers can fall back to local scan statuses.
    private func fetchPendingSyncCountFromServer() async throws -> Int? {
        do {
            let summaries = try await syncService.fetchSyncStatus()
            return summaries.reduce(0) { $0 + $1.unresolvedCount }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }
}
