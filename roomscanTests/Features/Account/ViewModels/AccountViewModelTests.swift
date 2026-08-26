//
//  AccountViewModelTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

@MainActor
struct AccountViewModelTests {
    @Test func loadMetricsAggregatesScansSharedProjectsAndStorage() async {
        let projects = [
            ProjectSummary(
                id: "p1",
                name: "One",
                ownerName: "You",
                createdAt: Date(),
                updatedAt: Date(),
                description: "",
                sharedUserCount: 0,
                roomScans: [
                    makeScan(id: "s1", syncStatus: .synced),
                    makeScan(id: "s2", syncStatus: .uploading),
                    makeScan(
                        id: "s3",
                        syncStatus: .failed,
                        localModelURL: URL(fileURLWithPath: "/tmp/mesh.usdz")
                    )
                ]
            )
        ]
        let sharedProjects = [
            SharedProjectItem(
                id: "shared-1",
                name: "Shared",
                ownerName: "Owner",
                scanCount: 1,
                thumbnailName: nil,
                status: .active,
                statusChangedAt: Date(),
                detailProject: nil
            ),
            SharedProjectItem(
                id: "shared-2",
                name: "Shared Two",
                ownerName: "Owner",
                scanCount: 2,
                thumbnailName: nil,
                status: .active,
                statusChangedAt: Date(),
                detailProject: nil
            )
        ]

        let viewModel = AccountViewModel(
            projectsService: MockProjectsService(
                projects: projects,
                simulatedDelayNanoseconds: 0
            ),
            sharedService: MockSharedService(
                projects: sharedProjects,
                scans: [],
                simulatedDelayNanoseconds: 0
            ),
            syncService: MockSyncService(simulatedDelayNanoseconds: 0),
            storageMeasuring: MockAccountStorageMeasuring(usedBytesValue: 1_800_000_000)
        )

        await viewModel.loadMetrics()

        #expect(viewModel.metrics?.localScanCount == 3)
        #expect(viewModel.metrics?.pendingSyncCount == 2)
        #expect(viewModel.metrics?.sharedProjectCount == 2)
        #expect(viewModel.metrics?.storageUsedBytes == 1_800_000_000)
        #expect(viewModel.metrics?.showsSyncPendingBanner == true)
    }

    @Test func loadMetricsPrefersServerSyncStatusTotals() async {
        let projects = [
            ProjectSummary(
                id: "p1",
                name: "One",
                ownerName: "You",
                createdAt: Date(),
                updatedAt: Date(),
                description: "",
                sharedUserCount: 0,
                roomScans: [
                    makeScan(id: "s1", syncStatus: .synced),
                    makeScan(id: "s2", syncStatus: .synced)
                ]
            )
        ]

        let viewModel = AccountViewModel(
            projectsService: MockProjectsService(
                projects: projects,
                simulatedDelayNanoseconds: 0
            ),
            sharedService: MockSharedService(
                projects: [],
                scans: [],
                simulatedDelayNanoseconds: 0
            ),
            syncService: MockSyncService(
                items: [
                    ProjectSyncStatusSummary(
                        projectId: "p1",
                        syncStatus: .pending,
                        pendingCount: 1,
                        syncingCount: 2,
                        failedCount: 1,
                        conflictCount: 0,
                        lastSyncedAt: nil,
                        requiredAssetsUploaded: false
                    )
                ],
                simulatedDelayNanoseconds: 0
            ),
            storageMeasuring: MockAccountStorageMeasuring(usedBytesValue: 0)
        )

        await viewModel.loadMetrics()

        #expect(viewModel.metrics?.pendingSyncCount == 4)
        #expect(viewModel.metrics?.showsSyncPendingBanner == true)
        #expect(viewModel.metrics?.localScanCount == 2)
    }

    @Test func loadMetricsUsesLocalPendingWhenHigherThanServer() async {
        let projects = [
            ProjectSummary(
                id: "p1",
                name: "One",
                ownerName: "You",
                createdAt: Date(),
                updatedAt: Date(),
                description: "",
                sharedUserCount: 0,
                roomScans: [
                    makeScan(id: "s1", syncStatus: .uploading),
                    makeScan(
                        id: "s2",
                        syncStatus: .failed,
                        localModelURL: URL(fileURLWithPath: "/tmp/mesh.usdz")
                    )
                ]
            )
        ]

        let viewModel = AccountViewModel(
            projectsService: MockProjectsService(
                projects: projects,
                simulatedDelayNanoseconds: 0
            ),
            sharedService: MockSharedService(
                projects: [],
                scans: [],
                simulatedDelayNanoseconds: 0
            ),
            syncService: MockSyncService(
                items: [
                    ProjectSyncStatusSummary(
                        projectId: "p1",
                        syncStatus: .synced,
                        pendingCount: 0,
                        syncingCount: 0,
                        failedCount: 0,
                        conflictCount: 0,
                        lastSyncedAt: Date(),
                        requiredAssetsUploaded: true
                    )
                ],
                simulatedDelayNanoseconds: 0
            ),
            storageMeasuring: MockAccountStorageMeasuring(usedBytesValue: 0)
        )

        await viewModel.loadMetrics()

        #expect(viewModel.metrics?.pendingSyncCount == 2)
        #expect(viewModel.metrics?.showsSyncPendingBanner == true)
    }

    @Test func loadMetricsFallsBackToLocalPendingCountWhenSyncStatusFails() async {
        let projects = [
            ProjectSummary(
                id: "p1",
                name: "One",
                ownerName: "You",
                createdAt: Date(),
                updatedAt: Date(),
                description: "",
                sharedUserCount: 0,
                roomScans: [
                    makeScan(id: "s1", syncStatus: .synced),
                    makeScan(
                        id: "s2",
                        syncStatus: .failed,
                        localModelURL: URL(fileURLWithPath: "/tmp/mesh.usdz")
                    )
                ]
            )
        ]

        let syncService = MockSyncService(
            items: [],
            scenario: .failLoad,
            simulatedDelayNanoseconds: 0
        )

        let viewModel = AccountViewModel(
            projectsService: MockProjectsService(
                projects: projects,
                simulatedDelayNanoseconds: 0
            ),
            sharedService: MockSharedService(
                projects: [],
                scans: [],
                simulatedDelayNanoseconds: 0
            ),
            syncService: syncService,
            storageMeasuring: MockAccountStorageMeasuring(usedBytesValue: 0)
        )

        await viewModel.loadMetrics()

        #expect(viewModel.metrics?.pendingSyncCount == 1)
        #expect(viewModel.metrics?.showsSyncPendingBanner == true)
        #expect(viewModel.loadFailed == false)
    }

    @Test func loadMetricsIgnoresStaleFailedWithoutLocalMeshWhenServerIsClear() async {
        let projects = [
            ProjectSummary(
                id: "p1",
                name: "One",
                ownerName: "You",
                createdAt: Date(),
                updatedAt: Date(),
                description: "",
                sharedUserCount: 0,
                roomScans: [
                    makeScan(id: "s1", syncStatus: .failed),
                    makeScan(id: "s2", syncStatus: .uploading)
                ]
            )
        ]

        let viewModel = AccountViewModel(
            projectsService: MockProjectsService(
                projects: projects,
                simulatedDelayNanoseconds: 0
            ),
            sharedService: MockSharedService(
                projects: [],
                scans: [],
                simulatedDelayNanoseconds: 0
            ),
            syncService: MockSyncService(
                items: [
                    ProjectSyncStatusSummary(
                        projectId: "p1",
                        syncStatus: .synced,
                        pendingCount: 0,
                        syncingCount: 0,
                        failedCount: 0,
                        conflictCount: 0,
                        lastSyncedAt: Date(),
                        requiredAssetsUploaded: true
                    )
                ],
                simulatedDelayNanoseconds: 0
            ),
            storageMeasuring: MockAccountStorageMeasuring(usedBytesValue: 0)
        )

        await viewModel.loadMetrics()

        #expect(viewModel.metrics?.pendingSyncCount == 1)
        #expect(viewModel.metrics?.showsSyncPendingBanner == true)
    }

    @Test func loadMetricsAggregatesAllScansAcrossPaginationPages() async {
        let projectCount = 101
        let projects = (0..<projectCount).map { index in
            ProjectSummary(
                id: "page-project-\(index)",
                name: "Project \(index)",
                ownerName: "You",
                createdAt: Date(),
                updatedAt: Date(),
                description: "",
                sharedUserCount: 0,
                roomScans: [makeScan(id: "page-scan-\(index)", syncStatus: .synced)]
            )
        }

        let viewModel = AccountViewModel(
            projectsService: MockProjectsService(
                projects: projects,
                simulatedDelayNanoseconds: 0
            ),
            sharedService: MockSharedService(
                projects: [],
                scans: [],
                simulatedDelayNanoseconds: 0
            ),
            syncService: MockSyncService(simulatedDelayNanoseconds: 0),
            storageMeasuring: MockAccountStorageMeasuring(usedBytesValue: 0)
        )

        await viewModel.loadMetrics()

        #expect(viewModel.metrics?.localScanCount == projectCount)
    }

    @Test func syncBannerHiddenWhenAllScansSynced() async {
        let projects = [
            ProjectSummary(
                id: "p1",
                name: "One",
                ownerName: "You",
                createdAt: Date(),
                updatedAt: Date(),
                description: "",
                sharedUserCount: 0,
                roomScans: [
                    makeScan(id: "s1", syncStatus: .synced),
                    makeScan(id: "s2", syncStatus: .synced)
                ]
            )
        ]

        let viewModel = AccountViewModel(
            projectsService: MockProjectsService(
                projects: projects,
                simulatedDelayNanoseconds: 0
            ),
            sharedService: MockSharedService(
                projects: [],
                scans: [],
                simulatedDelayNanoseconds: 0
            ),
            syncService: MockSyncService(simulatedDelayNanoseconds: 0),
            storageMeasuring: MockAccountStorageMeasuring(usedBytesValue: 0)
        )

        await viewModel.loadMetrics()

        #expect(viewModel.metrics?.pendingSyncCount == 0)
        #expect(viewModel.metrics?.showsSyncPendingBanner == false)
    }

    @Test func initialLoadFailurePreservesMissingState() async {
        let viewModel = AccountViewModel(
            projectsService: MockProjectsService(
                scenario: .failPage(1),
                simulatedDelayNanoseconds: 0
            ),
            sharedService: MockSharedService(simulatedDelayNanoseconds: 0),
            syncService: MockSyncService(simulatedDelayNanoseconds: 0),
            storageMeasuring: MockAccountStorageMeasuring()
        )

        await viewModel.loadMetrics()

        #expect(viewModel.metrics == nil)
        #expect(viewModel.loadFailed)
        #expect(viewModel.isLoading == false)
    }

    @Test func refreshFailureRetainsStaleMetricsAndExposesFailure() async {
        let sharedService = MockSharedService(
            projects: [],
            scans: [],
            simulatedDelayNanoseconds: 0
        )
        let viewModel = AccountViewModel(
            projectsService: MockProjectsService(simulatedDelayNanoseconds: 0),
            sharedService: sharedService,
            syncService: MockSyncService(simulatedDelayNanoseconds: 0),
            storageMeasuring: MockAccountStorageMeasuring(usedBytesValue: 1_000)
        )

        await viewModel.loadMetrics()
        #expect(viewModel.metrics != nil)
        #expect(viewModel.loadFailed == false)

        await sharedService.setScenario(.failLoad)
        await viewModel.loadMetrics()

        #expect(viewModel.metrics != nil)
        #expect(viewModel.loadFailed)
        #expect(viewModel.isLoading == false)
    }

    @Test func retryAfterFailureRecovers() async {
        let sharedService = MockSharedService(
            projects: [],
            scans: [],
            simulatedDelayNanoseconds: 0
        )
        let viewModel = AccountViewModel(
            projectsService: MockProjectsService(simulatedDelayNanoseconds: 0),
            sharedService: sharedService,
            syncService: MockSyncService(simulatedDelayNanoseconds: 0),
            storageMeasuring: MockAccountStorageMeasuring(usedBytesValue: 2_000)
        )

        await sharedService.setScenario(.failLoad)
        await viewModel.loadMetrics()
        #expect(viewModel.metrics == nil)
        #expect(viewModel.loadFailed)

        await sharedService.setScenario(.success)
        await viewModel.loadMetrics()

        #expect(viewModel.metrics != nil)
        #expect(viewModel.loadFailed == false)
    }

    @Test func signOutConfirmationFlow() {
        let viewModel = AccountViewModel(
            projectsService: MockProjectsService(simulatedDelayNanoseconds: 0),
            sharedService: MockSharedService(simulatedDelayNanoseconds: 0),
            syncService: MockSyncService(simulatedDelayNanoseconds: 0),
            storageMeasuring: MockAccountStorageMeasuring()
        )
        var didSignOut = false

        viewModel.requestSignOut()
        #expect(viewModel.showsSignOutConfirmation)

        viewModel.dismissSignOutConfirmation()
        #expect(viewModel.showsSignOutConfirmation == false)

        viewModel.requestSignOut()
        viewModel.confirmSignOut {
            didSignOut = true
        }

        #expect(didSignOut)
        #expect(viewModel.showsSignOutConfirmation == false)
    }
}

private func makeScan(
    id: String,
    syncStatus: RoomScanSyncStatus,
    localModelURL: URL? = nil
) -> RoomScanSummary {
    RoomScanSummary(
        id: id,
        name: id,
        createdAt: Date(),
        localModelURL: localModelURL,
        thumbnailName: "thumb",
        syncStatus: syncStatus,
        creatorUserID: "mock-user-apple",
        creatorDisplayName: "Mock Apple User",
        notes: []
    )
}
