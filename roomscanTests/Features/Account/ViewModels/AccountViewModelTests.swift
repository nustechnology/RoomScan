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
                    makeScan(id: "s3", syncStatus: .failed)
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
            storageMeasuring: MockAccountStorageMeasuring(usedBytesValue: 1_800_000_000)
        )

        await viewModel.loadMetrics()

        #expect(viewModel.metrics?.localScanCount == 3)
        #expect(viewModel.metrics?.pendingSyncCount == 2)
        #expect(viewModel.metrics?.sharedProjectCount == 2)
        #expect(viewModel.metrics?.storageUsedBytes == 1_800_000_000)
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

    @Test func displayNameInitialsAndProviderSubtitle() {
        #expect(AccountDisplayName.initials(from: "Mike Nguyen") == "MN")
        #expect(AccountDisplayName.initials(from: "Madonna") == "MA")
        #expect(AccountDisplayName.resolved(from: "  ") == String(localized: "account.defaultName"))
        #expect(AuthenticationProvider.apple.signedInSubtitle == String(localized: "account.signedIn.apple"))
        #expect(AuthenticationProvider.google.signedInSubtitle == String(localized: "account.signedIn.google"))
        #expect(AuthenticationProvider.facebook.signedInSubtitle == String(localized: "account.signedIn.facebook"))
    }

    private func makeScan(id: String, syncStatus: RoomScanSyncStatus) -> RoomScanSummary {
        RoomScanSummary(
            id: id,
            name: id,
            createdAt: Date(),
            localModelURL: nil,
            thumbnailName: "thumb",
            syncStatus: syncStatus,
            creatorUserID: "mock-user-apple",
            creatorDisplayName: "Mock Apple User",
            notes: []
        )
    }
}
