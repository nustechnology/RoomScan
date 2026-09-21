//
//  SharedWithMeViewModelTests.swift
//  roomscanTests
//

import Foundation
import Testing
@testable import roomscan

@MainActor
struct SharedWithMeViewModelTests {
    @Test func loadsProjectsAndScansExcludingExpiredInactiveItems() async {
        let now = Date()
        let service = MockSharedService(
            projects: MockSharedService.makeSeedProjects(now: now),
            scans: MockSharedService.makeSeedScans(now: now),
            simulatedDelayNanoseconds: 0,
            now: now
        )
        let viewModel = SharedWithMeViewModel(service: service)

        await viewModel.loadInitialContent()

        #expect(viewModel.projectsViewState == .loaded)
        #expect(viewModel.scansViewState == .loaded)
        #expect(viewModel.projects.map(\.id).contains("shared-project-expired") == false)
        #expect(viewModel.scans.map(\.id).contains("shared-scan-expired") == false)
        #expect(viewModel.projects.contains(where: { $0.id == "shared-project-active" }))
        #expect(viewModel.scans.contains(where: { $0.id == "shared-scan-active" }))
    }

    @Test func activeProjectTapReturnsDetail() async {
        let service = MockSharedService(simulatedDelayNanoseconds: 0)
        let viewModel = SharedWithMeViewModel(service: service)
        await viewModel.loadInitialContent()

        let result = viewModel.handleItemTap(scope: .project, id: "shared-project-active")

        #expect(result != nil)
        if case .openProject(let project)? = result {
            #expect(project.id == "shared-project-active")
        } else {
            Issue.record("Expected openProject result")
        }
        #expect(viewModel.pendingAlert == nil)
    }

    @Test func activeProjectWithoutDetailDoesNotShowInactiveAlert() async {
        let activeWithoutDetail = SharedProjectItem(
            id: "shared-project-active-no-detail",
            name: "Broken Active Project",
            ownerName: "Owner",
            scanCount: 1,
            thumbnailName: nil,
            status: .active,
            statusChangedAt: Date(),
            detailProject: nil
        )
        let service = MockSharedService(
            projects: [activeWithoutDetail],
            scans: [],
            simulatedDelayNanoseconds: 0
        )
        let viewModel = SharedWithMeViewModel(service: service)
        await viewModel.loadInitialContent()

        let result = viewModel.handleItemTap(scope: .project, id: activeWithoutDetail.id)

        #expect(result == nil)
        #expect(viewModel.pendingAlert == nil)
    }

    @Test func inactiveProjectTapShowsAlert() async {
        let service = MockSharedService(simulatedDelayNanoseconds: 0)
        let viewModel = SharedWithMeViewModel(service: service)
        await viewModel.loadInitialContent()

        let result = viewModel.handleItemTap(scope: .project, id: "shared-project-revoked")

        #expect(result == nil)
        #expect(viewModel.pendingAlert == .inactiveTap(
            scope: .project,
            id: "shared-project-revoked",
            status: .accessRevoked
        ))
    }

    @Test func confirmingRemoveDeletesItemAndShowsToast() async {
        let service = MockSharedService(simulatedDelayNanoseconds: 0)
        let viewModel = SharedWithMeViewModel(service: service)
        await viewModel.loadInitialContent()
        viewModel.requestRemove(scope: .project, id: "shared-project-active")

        await viewModel.confirmPendingAlertAction()

        #expect(viewModel.projects.contains(where: { $0.id == "shared-project-active" }) == false)
        #expect(viewModel.toastMessage == String(localized: "shared.remove.toast"))
        #expect(viewModel.pendingAlert == nil)
    }

    @Test func removalRequestIsIgnoredWhileAnotherRemovalIsRunning() async {
        let removalStarted = OperationStartSignal()
        let service = MockSharedService(simulatedDelayNanoseconds: 100_000_000)
        await service.setBeforeRemove {
            await removalStarted.markStarted()
        }
        let viewModel = SharedWithMeViewModel(service: service)
        await viewModel.loadInitialContent()
        viewModel.requestRemove(scope: .project, id: "shared-project-active")

        let removalTask = Task { await viewModel.confirmPendingAlertAction() }
        await removalStarted.waitUntilStarted()
        #expect(viewModel.isRemovingItem)

        viewModel.requestRemove(scope: .scan, id: "shared-scan-active")

        #expect(viewModel.pendingAlert == nil)
        await removalTask.value
    }

    @Test func removeFailurePreservesProjectAndShowsErrorToast() async {
        let service = MockSharedService(simulatedDelayNanoseconds: 0)
        let viewModel = SharedWithMeViewModel(service: service)
        await viewModel.loadInitialContent()
        let loadedIDs = viewModel.projects.map(\.id)

        await service.setScenario(.failLoad)
        viewModel.requestRemove(scope: .project, id: "shared-project-active")
        await viewModel.confirmPendingAlertAction()

        #expect(viewModel.projects.map(\.id) == loadedIDs)
        #expect(viewModel.projectsViewState == .loaded)
        #expect(viewModel.toastMessage == String(localized: "shared.action.error"))
        #expect(viewModel.pendingAlert == nil)
    }

    @Test func removeFailurePreservesScanAndShowsErrorToast() async {
        let service = MockSharedService(simulatedDelayNanoseconds: 0)
        let viewModel = SharedWithMeViewModel(service: service)
        await viewModel.loadInitialContent()
        let loadedIDs = viewModel.scans.map(\.id)

        await service.setScenario(.failLoad)
        viewModel.requestRemove(scope: .scan, id: "shared-scan-active")
        await viewModel.confirmPendingAlertAction()

        #expect(viewModel.scans.map(\.id) == loadedIDs)
        #expect(viewModel.scansViewState == .loaded)
        #expect(viewModel.toastMessage == String(localized: "shared.action.error"))
        #expect(viewModel.pendingAlert == nil)
    }

    @Test func concurrentInitialLoadDoesNotLeaveProjectsStuckLoading() async {
        let service = MockSharedService(simulatedDelayNanoseconds: 50_000_000)
        let viewModel = SharedWithMeViewModel(service: service)

        await viewModel.loadInitialContent()

        #expect(viewModel.projectsViewState == .loaded)
        #expect(viewModel.scansViewState == .loaded)
        #expect(viewModel.projects.isEmpty == false)
        #expect(viewModel.scans.isEmpty == false)
    }

    @Test func emptyScenarioShowsEmptyStates() async {
        let service = MockSharedService(scenario: .empty, simulatedDelayNanoseconds: 0)
        let viewModel = SharedWithMeViewModel(service: service)

        await viewModel.loadInitialContent()

        #expect(viewModel.projectsViewState == .empty)
        #expect(viewModel.scansViewState == .empty)
    }

    @Test func refreshFailurePreservesLoadedProjectsAndShowsErrorToast() async {
        let service = MockSharedService(simulatedDelayNanoseconds: 0)
        let viewModel = SharedWithMeViewModel(service: service)
        await viewModel.loadInitialContent()
        let loadedIDs = viewModel.projects.map(\.id)

        await service.setScenario(.failLoad)
        await viewModel.refreshSelectedTab()

        #expect(viewModel.projects.map(\.id) == loadedIDs)
        #expect(viewModel.projectsViewState == .loaded)
        #expect(viewModel.toastMessage == String(localized: "shared.action.error"))
    }

    @Test func refreshFailurePreservesLoadedScansAndShowsErrorToast() async {
        let service = MockSharedService(simulatedDelayNanoseconds: 0)
        let viewModel = SharedWithMeViewModel(service: service)
        await viewModel.loadInitialContent()
        viewModel.selectSubTab(.scans)
        let loadedIDs = viewModel.scans.map(\.id)

        await service.setScenario(.failLoad)
        await viewModel.refreshSelectedTab()

        #expect(viewModel.scans.map(\.id) == loadedIDs)
        #expect(viewModel.scansViewState == .loaded)
        #expect(viewModel.toastMessage == String(localized: "shared.action.error"))
    }

    @Test func initialLoadFailureUsesFailedStateWithoutToast() async {
        let service = MockSharedService(scenario: .failLoad, simulatedDelayNanoseconds: 0)
        let viewModel = SharedWithMeViewModel(service: service)

        await viewModel.loadInitialContent()

        #expect(viewModel.projectsViewState == .failed)
        #expect(viewModel.scansViewState == .failed)
        #expect(viewModel.projects.isEmpty)
        #expect(viewModel.scans.isEmpty)
        #expect(viewModel.toastMessage == nil)
    }

    @Test func cancelledInitialLoadResetsToIdleAndRetriesOnReappear() async {
        let service = MockSharedService(scenario: .cancelled, simulatedDelayNanoseconds: 0)
        let viewModel = SharedWithMeViewModel(service: service)

        await viewModel.loadInitialContent()

        #expect(viewModel.projectsViewState == .idle)
        #expect(viewModel.scansViewState == .idle)
        #expect(viewModel.projects.isEmpty)
        #expect(viewModel.scans.isEmpty)
        #expect(viewModel.toastMessage == nil)

        await service.setScenario(.success)
        await viewModel.loadInitialContent()

        #expect(viewModel.projectsViewState == .loaded)
        #expect(viewModel.scansViewState == .loaded)
        #expect(viewModel.projects.isEmpty == false)
        #expect(viewModel.scans.isEmpty == false)
    }

    @Test func cancellingConsumingLoadTaskStillAppliesFetchKeepingAliveResults() async {
        let fetchGate = FetchReleaseGate()
        let service = MockSharedService(simulatedDelayNanoseconds: 0)
        await service.setBeforeFetch {
            await fetchGate.markStartedAndWaitForRelease()
        }
        let viewModel = SharedWithMeViewModel(service: service)

        let loadTask = Task {
            await viewModel.loadInitialContent()
        }

        await fetchGate.waitUntilStarted()
        loadTask.cancel()
        await fetchGate.release()
        _ = await loadTask.result

        #expect(viewModel.projectsViewState == .loaded)
        #expect(viewModel.scansViewState == .loaded)
        #expect(viewModel.projects.isEmpty == false)
        #expect(viewModel.scans.isEmpty == false)
        #expect(viewModel.toastMessage == nil)
    }

    @Test func fetchReleaseGateReleaseBeforeOperationWaitsDoesNotHang() async {
        let fetchGate = FetchReleaseGate()

        // Simulates release() winning the race to the `released` signal before the
        // fetch operation calls markStartedAndWaitForRelease(). If the underlying
        // OperationStartSignal were edge-triggered, this would hang forever.
        await fetchGate.release()
        await fetchGate.markStartedAndWaitForRelease()
    }

    @Test func failedAcceptedProjectIngestAppearsAfterSuccessfulRefresh() async {
        let project = ProjectSummary(
            id: "accepted-project",
            name: "Accepted Project",
            ownerName: "Owner",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            description: "Shared via invitation",
            sharedUserCount: 1,
            roomScans: []
        )
        let destination = AcceptedInvitationDestination.project(project)
        let service = MockSharedService(
            scenario: .empty,
            projects: [],
            scans: [],
            simulatedDelayNanoseconds: 0
        )
        let viewModel = SharedWithMeViewModel(service: service)
        await viewModel.loadInitialContent()

        await service.setScenario(.failLoad)
        await viewModel.ingestAcceptedDestination(destination)
        await viewModel.refreshAllContent()
        #expect(viewModel.projects.contains(where: { $0.id == project.id }) == false)

        await service.setScenario(.success)
        await viewModel.refreshAllContent()

        #expect(viewModel.projects.contains(where: { $0.id == project.id }))
        #expect(viewModel.projectsViewState == .loaded)
    }

    @Test func failedAcceptedScanIngestAppearsAfterSuccessfulRefresh() async {
        let scan = SharedScanItem.make(
            from: RoomScanSummary(
                id: "accepted-scan",
                name: "Accepted Scan",
                createdAt: Date(timeIntervalSince1970: 1_500),
                localModelURL: nil,
                thumbnailName: "thumbnail",
                syncStatus: .synced,
                creatorUserID: "owner-1",
                creatorDisplayName: "Owner",
                notes: []
            ),
            parent: SharedScanParent(
                ownerName: "Owner",
                projectID: "shared-project",
                projectName: "Shared Project"
            ),
            status: .active,
            statusChangedAt: Date(timeIntervalSince1970: 1_500)
        )
        let destination = AcceptedInvitationDestination.scan(scan)
        let service = MockSharedService(
            scenario: .empty,
            projects: [],
            scans: [],
            simulatedDelayNanoseconds: 0
        )
        let viewModel = SharedWithMeViewModel(service: service)
        await viewModel.loadInitialContent()
        viewModel.selectSubTab(.scans)

        await service.setScenario(.failLoad)
        await viewModel.ingestAcceptedDestination(destination)
        await viewModel.refreshSelectedTab()
        #expect(viewModel.scans.contains(where: { $0.id == scan.id }) == false)

        await service.setScenario(.success)
        await viewModel.refreshSelectedTab()

        #expect(viewModel.scans.contains(where: { $0.id == scan.id }))
        #expect(viewModel.scansViewState == .loaded)
    }
}

/// Level-triggered: once `markStarted()` has run, every subsequent (and in-flight)
/// `waitUntilStarted()` call resumes immediately instead of waiting for a fresh signal.
/// This makes the signal safe to fire before a waiter has registered, which matters
/// because `FetchReleaseGate.release()` can legitimately race ahead of the operation's
/// own call into `markStartedAndWaitForRelease()`.
private actor OperationStartSignal {
    private var hasStarted = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            if hasStarted {
                continuation.resume()
                return
            }
            continuations.append(continuation)
        }
    }

    func markStarted() {
        guard !hasStarted else { return }
        hasStarted = true
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}

/// Starts one signal, then waits on a second signal that `release()` fires.
private actor FetchReleaseGate {
    private let started = OperationStartSignal()
    private let released = OperationStartSignal()

    func waitUntilStarted() async {
        await started.waitUntilStarted()
    }

    func release() async {
        await released.markStarted()
    }

    func markStartedAndWaitForRelease() async {
        await started.markStarted()
        await released.waitUntilStarted()
    }
}

struct SharedInactiveRetentionTests {
    @Test func retainsActiveItemsRegardlessOfAge() {
        let now = Date()
        let oldDate = now.addingTimeInterval(-30 * 86_400)

        #expect(SharedInactiveRetention.shouldRetain(
            status: .active,
            statusChangedAt: oldDate,
            now: now
        ))
    }

    @Test func retainsInactiveItemsWithinSevenDays() {
        let now = Date()
        let sixDaysAgo = now.addingTimeInterval(-6 * 86_400)

        #expect(SharedInactiveRetention.shouldRetain(
            status: .accessRevoked,
            statusChangedAt: sixDaysAgo,
            now: now
        ))
    }

    @Test func dropsInactiveItemsAfterSevenDays() {
        let now = Date()
        let eightDaysAgo = now.addingTimeInterval(-8 * 86_400)

        #expect(SharedInactiveRetention.shouldRetain(
            status: .itemDeleted,
            statusChangedAt: eightDaysAgo,
            now: now
        ) == false)
    }
}

struct SharedProjectThumbnailTests {
    @Test func usesThumbnailFromMostRecentlyCreatedScan() {
        let older = RoomScanSummary(
            id: "older",
            name: "Older",
            createdAt: Date(timeIntervalSince1970: 1_000),
            localModelURL: nil,
            thumbnailName: "older-thumb",
            syncStatus: .synced,
            creatorUserID: "u1",
            creatorDisplayName: "Owner",
            notes: []
        )
        let newer = RoomScanSummary(
            id: "newer",
            name: "Newer",
            createdAt: Date(timeIntervalSince1970: 2_000),
            localModelURL: nil,
            thumbnailName: "newer-thumb",
            syncStatus: .synced,
            creatorUserID: "u1",
            creatorDisplayName: "Owner",
            notes: []
        )

        #expect(SharedProjectItem.thumbnailName(from: [older, newer]) == "newer-thumb")
    }

    @Test func returnsNilThumbnailWhenProjectHasNoScans() {
        #expect(SharedProjectItem.thumbnailName(from: []) == nil)
    }

    @Test func seedIncludesZeroScanProjectWithPlaceholderThumbnail() {
        let projects = MockSharedService.makeSeedProjects()
        let emptyProject = projects.first { $0.id == "shared-project-empty-scans" }

        #expect(emptyProject != nil)
        #expect(emptyProject?.scanCount == 0)
        #expect(emptyProject?.thumbnailName == nil)
        #expect(emptyProject?.status == .active)
    }

    @Test func seedActiveProjectThumbnailMatchesMostRecentScan() {
        let projects = MockSharedService.makeSeedProjects()
        let active = projects.first { $0.id == "shared-project-active" }
        let mostRecentThumb = active?.detailProject.flatMap {
            SharedProjectItem.thumbnailName(from: $0.roomScans)
        }

        #expect(active?.thumbnailName == mostRecentThumb)
        #expect(active?.thumbnailName == "ScanThumbnail")
    }
}

struct SharedProjectItemCoalescingTests {
    @Test func activeStubDoesNotWipeAcceptedDetail() {
        let accepted = SharedProjectItem.make(
            from: ProjectSummary(
                id: "accepted-project",
                name: "Accepted Villa",
                ownerName: "owner@example.com",
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 2),
                description: "",
                sharedUserCount: 1,
                roomScans: []
            ),
            status: .active,
            statusChangedAt: Date(timeIntervalSince1970: 2)
        )
        let syncStub = SharedProjectItem(
            id: "accepted-project",
            name: "",
            ownerName: "",
            scanCount: 0,
            thumbnailName: nil,
            status: .active,
            statusChangedAt: Date(timeIntervalSince1970: 3),
            detailProject: nil
        )

        let merged = SharedProjectItem.coalescing(existing: accepted, incoming: syncStub)

        #expect(merged.name == "Accepted Villa")
        #expect(merged.detailProject != nil)
        #expect(merged.statusChangedAt == Date(timeIntervalSince1970: 3))
    }

    @Test func newerRevocationReplacesAcceptedDetail() {
        let accepted = SharedProjectItem.make(
            from: ProjectSummary(
                id: "accepted-project",
                name: "Accepted Villa",
                ownerName: "owner@example.com",
                roomScans: []
            ),
            status: .active,
            statusChangedAt: Date(timeIntervalSince1970: 2)
        )
        let revoked = SharedProjectItem(
            id: "accepted-project",
            name: "",
            ownerName: "",
            scanCount: 0,
            thumbnailName: nil,
            status: .accessRevoked,
            statusChangedAt: Date(timeIntervalSince1970: 4),
            detailProject: nil
        )

        let merged = SharedProjectItem.coalescing(existing: accepted, incoming: revoked)

        #expect(merged.status == .accessRevoked)
        #expect(merged.detailProject == nil)
    }
}
