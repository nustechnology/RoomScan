//
//  ScanDetailViewModelTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

@MainActor
struct ScanDetailViewModelTests {
    /// Matches `AuthenticationSession.mockAppleUser` without crossing MainActor isolation.
    private nonisolated static let mockCurrentUserID = "mock-user-apple"
    private nonisolated static let mockCurrentUserDisplayName = "Mock Apple User"

    @Test func createdByShowsYouForCurrentUser() {
        let viewModel = makeViewModel()

        #expect(viewModel.createdByText == String(localized: "scanDetail.createdBy.you"))
    }

    @Test func createdByShowsCreatorNameForOtherUser() {
        let viewModel = makeViewModel(
            creatorUserID: "other-user",
            creatorDisplayName: "Alex Rivera"
        )

        #expect(viewModel.createdByText == "Alex Rivera")
    }

    @Test func createdByPrefersCreatorNameAfterRemoteDetailLoads() async {
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(
                creatorUserID: "other-user",
                creatorDisplayName: "Alex Rivera"
            ),
            currentUserID: Self.mockCurrentUserID,
            service: MockProjectsService(projects: [makeProject()], simulatedDelayNanoseconds: 0),
            scanDetailService: ScanDetailRenameStub(
                creatorID: "other-user",
                creatorEmail: "alex@example.com"
            ),
            accessPolicy: .readOnly
        )

        await viewModel.loadDetail()

        #expect(viewModel.createdByText == "Alex Rivera")
    }

    @Test func createdByUsesRemoteDisplayNameForScanInsideSharedProject() async {
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(
                creatorUserID: "",
                creatorDisplayName: ""
            ),
            currentUserID: Self.mockCurrentUserID,
            service: MockProjectsService(projects: [makeProject()], simulatedDelayNanoseconds: 0),
            scanDetailService: ScanDetailRenameStub(
                creatorID: "other-user",
                creatorDisplayName: "Scan Creator",
                creatorEmail: "owner@example.com"
            ),
            accessPolicy: .readOnly,
            creatorDisplayNameFallback: "Project Owner"
        )

        await viewModel.loadDetail()

        #expect(viewModel.createdByText == "Scan Creator")
    }

    @Test func createdByUpgradesProjectOwnerFallbackToRemoteEmail() async {
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(
                creatorUserID: "",
                creatorDisplayName: ""
            ),
            currentUserID: Self.mockCurrentUserID,
            service: MockProjectsService(projects: [makeProject()], simulatedDelayNanoseconds: 0),
            scanDetailService: ScanDetailRenameStub(
                creatorID: "other-user",
                creatorEmail: "creator@example.com"
            ),
            accessPolicy: .readOnly,
            creatorDisplayNameFallback: "Project Owner"
        )

        #expect(viewModel.createdByText == "Project Owner")

        await viewModel.loadDetail()

        #expect(viewModel.createdByText == "creator@example.com")
    }

    @Test func createdByStillShowsYouAfterRemoteDetailLoads() async {
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(),
            currentUserID: Self.mockCurrentUserID,
            service: MockProjectsService(projects: [makeProject()], simulatedDelayNanoseconds: 0),
            scanDetailService: ScanDetailRenameStub(creatorEmail: "me@example.com")
        )

        await viewModel.loadDetail()

        #expect(viewModel.createdByText == String(localized: "scanDetail.createdBy.you"))
    }

    @Test func createdByShowsUnknownWhenCreatorIdentityIsBlank() async {
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(creatorUserID: "", creatorDisplayName: " "),
            currentUserID: Self.mockCurrentUserID,
            service: MockProjectsService(projects: [makeProject()], simulatedDelayNanoseconds: 0),
            scanDetailService: ScanDetailRenameStub(
                creatorID: "other-user",
                creatorDisplayName: " ",
                creatorEmail: " "
            ),
            accessPolicy: .readOnly
        )

        await viewModel.loadDetail()

        #expect(viewModel.createdByText == String(localized: "shared.owner.unknown"))
    }

    @Test func formattedDateDefaultsToUSOrder() {
        let viewModel = makeViewModel(
            createdAt: Date(timeIntervalSince1970: 1_781_251_200) // Jun 12, 2026 UTC
        )

        #expect(
            ScanDetailViewModel.formattedDate(
                for: viewModel.scan.createdAt,
                timeZone: TimeZone(secondsFromGMT: 0)!
            ) == "Jun 12, 2026"
        )
    }

    @Test func notesCountTextUsesNoteCount() {
        let viewModel = makeViewModel(noteCount: 3)
        #expect(viewModel.notesCountText == "3")
    }

    @Test func loadDetailUpdatesNotesCountFromRemote() async {
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(noteCount: 1),
            currentUserID: Self.mockCurrentUserID,
            service: MockProjectsService(projects: [makeProject()], simulatedDelayNanoseconds: 0),
            scanDetailService: ScanDetailRenameStub(noteCount: 4)
        )

        await viewModel.loadDetail()

        #expect(viewModel.notesCountText == "4")
        #expect(viewModel.scan.noteCount == 4)
    }

    @Test func silentLoadDetailRefreshesNotesCountWithoutLoadingFlag() async {
        let service = ScanDetailNoteCountStub(noteCounts: [1, 3])
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(noteCount: 1),
            currentUserID: Self.mockCurrentUserID,
            service: MockProjectsService(projects: [makeProject()], simulatedDelayNanoseconds: 0),
            scanDetailService: service
        )

        await viewModel.loadDetail()
        #expect(viewModel.notesCountText == "1")

        await viewModel.loadDetail(showsLoadingIndicator: false)

        #expect(!viewModel.isLoadingDetail)
        #expect(viewModel.notesCountText == "3")
        #expect(viewModel.scan.noteCount == 3)
    }

    @Test func silentLoadDetailSkippedWhileVisibleLoadIsInFlight() async {
        let service = DeferredSilentRefreshScanDetailStub(
            firstNoteCount: 1,
            refreshedNoteCount: 5
        )
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(name: "Living Room", noteCount: 0),
            currentUserID: Self.mockCurrentUserID,
            service: MockProjectsService(projects: [makeProject()], simulatedDelayNanoseconds: 0),
            scanDetailService: service
        )

        let visibleLoad = Task { await viewModel.loadDetail(showsLoadingIndicator: true) }
        await service.waitUntilFirstFetchIsSuspended()
        #expect(viewModel.isLoadingDetail)

        await viewModel.loadDetail(showsLoadingIndicator: false)
        #expect(await service.fetchCount() == 1)

        await service.releaseFirstFetch()
        await visibleLoad.value

        #expect(!viewModel.isLoadingDetail)
        #expect(await service.fetchCount() == 2)
        #expect(viewModel.notesCountText == "5")
        #expect(viewModel.scan.noteCount == 5)
    }

    @Test func loadDetailIgnoresSupersededResponseWhenLaterLoadFinishesFirst() async {
        let service = ReverseCompletionScanDetailStub(
            staleNoteCount: 2,
            latestNoteCount: 7
        )
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(noteCount: 1),
            currentUserID: Self.mockCurrentUserID,
            service: MockProjectsService(projects: [makeProject()], simulatedDelayNanoseconds: 0),
            scanDetailService: service
        )

        let firstLoad = Task { await viewModel.loadDetail(showsLoadingIndicator: false) }
        await service.waitUntilFirstFetchIsSuspended()
        await viewModel.loadDetail(showsLoadingIndicator: false)
        await firstLoad.value

        #expect(viewModel.notesCountText == "7")
        #expect(viewModel.scan.noteCount == 7)
    }

    @Test func successfulRenameInvalidatesInFlightDetailLoad() async {
        let service = SuspendedFetchScanDetailStub(staleName: "Living Room")
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(name: "Living Room"),
            currentUserID: Self.mockCurrentUserID,
            service: MockProjectsService(projects: [makeProject()], simulatedDelayNanoseconds: 0),
            scanDetailService: service
        )

        let inFlightLoad = Task { await viewModel.loadDetail(showsLoadingIndicator: false) }
        await service.waitUntilFetchIsSuspended()

        viewModel.renameDraft = "Dining Room"
        let didRename = await viewModel.renameScan()
        #expect(didRename)
        #expect(viewModel.title == "Dining Room")

        await service.releaseSuspendedFetch()
        await inFlightLoad.value

        #expect(viewModel.title == "Dining Room")
        #expect(viewModel.scan.name == "Dining Room")
    }

    @Test func successfulDeleteInvalidatesInFlightDetailLoad() async {
        let service = SuspendedFetchScanDetailStub(staleName: "Living Room")
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(name: "Living Room"),
            currentUserID: Self.mockCurrentUserID,
            service: MockProjectsService(projects: [makeProject()], simulatedDelayNanoseconds: 0),
            scanDetailService: service
        )

        let inFlightLoad = Task { await viewModel.loadDetail(showsLoadingIndicator: false) }
        await service.waitUntilFetchIsSuspended()

        let didDelete = await viewModel.deleteScan()
        #expect(didDelete)
        #expect(viewModel.didDeleteScan)
        #expect(viewModel.detail == nil)

        await service.releaseSuspendedFetch()
        await inFlightLoad.value

        #expect(viewModel.didDeleteScan)
        #expect(viewModel.detail == nil)
    }

    @Test func thumbnailPathUsesThumbnailFromDetail() async {
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(),
            currentUserID: Self.mockCurrentUserID,
            service: MockProjectsService(projects: [makeProject()], simulatedDelayNanoseconds: 0),
            scanDetailService: ScanDetailRenameStub(
                thumbnail: "https://roomscan.nustechnology.com/roomscan-assets/scans/scan-1/thumbnail"
            )
        )

        await viewModel.loadDetail()

        #expect(viewModel.thumbnailPath == "https://roomscan.nustechnology.com/roomscan-assets/scans/scan-1/thumbnail")
    }

    @Test func renameScanUpdatesTitle() async {
        let service = MockProjectsService(
            projects: [makeProject()],
            simulatedDelayNanoseconds: 0
        )
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(name: "Living Room"),
            currentUserID: Self.mockCurrentUserID,
            service: service,
            scanDetailService: ScanDetailRenameStub()
        )
        viewModel.renameDraft = "  Dining Room  "

        let didRename = await viewModel.renameScan()

        #expect(didRename)
        #expect(viewModel.title == "Dining Room")
        #expect(viewModel.scan.name == "Dining Room")
    }

    @Test func renameScanUsesLocalServiceWhenRemoteServiceIsNotInjected() async throws {
        let service = MockProjectsService(
            projects: [makeProject()],
            simulatedDelayNanoseconds: 0
        )
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(name: "Living Room"),
            currentUserID: Self.mockCurrentUserID,
            service: service
        )
        viewModel.renameDraft = "Dining Room"

        let didRename = await viewModel.renameScan()
        let projects = try await service.fetchAllProjectsSortedByUpdated()
        let project = try #require(projects.first)
        #expect(didRename)
        #expect(project.roomScans.first?.name == "Dining Room")
    }

    @Test func renameScanRejectsEmptyName() async {
        let service = MockProjectsService(
            projects: [makeProject()],
            simulatedDelayNanoseconds: 0
        )
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(name: "Living Room"),
            currentUserID: Self.mockCurrentUserID,
            service: service
        )
        viewModel.renameDraft = "   "

        let didRename = await viewModel.renameScan()

        #expect(!didRename)
        #expect(viewModel.showsActionError)
        #expect(viewModel.title == "Living Room")
    }

    @Test func renameScanRejectsDuplicateNameAndShowsExistingMessage() async {
        let scan = makeScan(id: "scan-1", name: "Living Room")
        let service = MockProjectsService(
            projects: [
                makeProject(roomScans: [
                    scan,
                    makeScan(id: "scan-2", name: "Kitchen")
                ])
            ],
            simulatedDelayNanoseconds: 0
        )
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: scan,
            currentUserID: Self.mockCurrentUserID,
            service: service,
            scanDetailService: ScanDetailRenameStub()
        )
        viewModel.renameDraft = "  kitchen  "

        let didRename = await viewModel.renameScan()

        #expect(!didRename)
        #expect(viewModel.showsActionError)
        #expect(viewModel.actionErrorMessage == String(localized: "review.error.duplicate_name"))
        #expect(viewModel.title == "Living Room")
    }

    @Test func renameScanAllowsUnchangedName() async {
        let scan = makeScan(name: "Living Room")
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: scan,
            currentUserID: Self.mockCurrentUserID,
            service: MockProjectsService(
                projects: [makeProject(roomScans: [scan])],
                simulatedDelayNanoseconds: 0
            ),
            scanDetailService: ScanDetailRenameStub()
        )
        viewModel.renameDraft = "  living room  "

        let didRename = await viewModel.renameScan()

        #expect(didRename)
        #expect(!viewModel.showsActionError)
    }

    @Test func renameScanShowsExistingMessageForServerConflict() async {
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(name: "Living Room"),
            currentUserID: Self.mockCurrentUserID,
            service: MockProjectsService(
                projects: [makeProject()],
                simulatedDelayNanoseconds: 0
            ),
            scanDetailService: DuplicateScanDetailRenameStub()
        )
        viewModel.renameDraft = "Kitchen"

        let didRename = await viewModel.renameScan()

        #expect(!didRename)
        #expect(viewModel.showsActionError)
        #expect(viewModel.actionErrorMessage == String(localized: "review.error.duplicate_name"))
        #expect(viewModel.title == "Living Room")
    }

    @Test func renameScanBeforeDetailLoadsOmitsDescription() async {
        let scanDetailService = ScanDetailRenameSpy()
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(name: "Living Room"),
            currentUserID: Self.mockCurrentUserID,
            service: MockProjectsService(
                projects: [makeProject()],
                simulatedDelayNanoseconds: 0
            ),
            scanDetailService: scanDetailService
        )
        viewModel.renameDraft = "Dining Room"

        let didRename = await viewModel.renameScan()
        let updateDescription = await scanDetailService.lastUpdateDescription()

        #expect(didRename)
        #expect(updateDescription == nil)
    }

    @Test func scanDetailUpdateRequestOmitsMissingDescription() throws {
        let data = try JSONEncoder().encode(
            ScanDetailUpdateRequest(name: "Dining Room", description: nil)
        )
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(body["name"] as? String == "Dining Room")
        #expect(body["description"] == nil)
    }

    @Test func deleteScanMarksDeletion() async {
        let service = MockProjectsService(
            projects: [makeProject()],
            simulatedDelayNanoseconds: 0
        )
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(),
            currentUserID: Self.mockCurrentUserID,
            service: service,
            scanDetailService: ScanDetailRenameStub()
        )

        let didDelete = await viewModel.deleteScan()

        #expect(didDelete)
        #expect(viewModel.didDeleteScan)
    }

    @Test func deleteScanUsesLocalServiceWhenRemoteServiceIsNotInjected() async throws {
        let service = MockProjectsService(
            projects: [makeProject()],
            simulatedDelayNanoseconds: 0
        )
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(),
            currentUserID: Self.mockCurrentUserID,
            service: service
        )

        let didDelete = await viewModel.deleteScan()
        let projects = try await service.fetchAllProjectsSortedByUpdated()
        let project = try #require(projects.first)
        #expect(didDelete)
        #expect(project.roomScans.isEmpty)
    }

    @Test func retryUploadUpdatesFailedStatusToSynced() async {
        let service = MockProjectsService(
            projects: [makeProject(syncStatus: .failed)],
            simulatedDelayNanoseconds: 0
        )
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(syncStatus: .failed),
            currentUserID: Self.mockCurrentUserID,
            service: service
        )

        #expect(viewModel.showsRetryUpload)

        let didRetry = await viewModel.retryUpload()

        #expect(didRetry)
        #expect(viewModel.scan.syncStatus == .synced)
        #expect(!viewModel.showsRetryUpload)
    }

    @Test func retryUploadUpdatesLoadedDetailStatus() async {
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(syncStatus: .failed),
            currentUserID: Self.mockCurrentUserID,
            service: MockProjectsService(
                projects: [makeProject(syncStatus: .failed)],
                simulatedDelayNanoseconds: 0
            ),
            scanDetailService: ScanDetailRetryStub()
        )

        await viewModel.loadDetail()
        #expect(viewModel.displaySyncStatus == .failed)

        let didRetry = await viewModel.retryUpload()

        #expect(didRetry)
        #expect(viewModel.displaySyncStatus == .synced)
        #expect(!viewModel.showsRetryUpload)
    }

    @Test func displaySyncStatusKeepsFailedWhenLocalMeshExists() async {
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(
                localModelURL: URL(fileURLWithPath: "/tmp/mesh.usdz"),
                syncStatus: .failed
            ),
            currentUserID: Self.mockCurrentUserID,
            service: MockProjectsService(
                projects: [makeProject(syncStatus: .failed)],
                simulatedDelayNanoseconds: 0
            ),
            scanDetailService: ScanDetailStatusStub(syncStatus: .pending)
        )

        await viewModel.loadDetail()

        #expect(viewModel.displaySyncStatus == .failed)
        #expect(viewModel.showsRetryUpload)
    }

    @Test func displaySyncStatusTrustsRemotePendingWhenFailedHasNoMesh() async {
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(syncStatus: .failed),
            currentUserID: Self.mockCurrentUserID,
            service: MockProjectsService(
                projects: [makeProject(syncStatus: .failed)],
                simulatedDelayNanoseconds: 0
            ),
            scanDetailService: ScanDetailStatusStub(syncStatus: .pending)
        )

        await viewModel.loadDetail()

        #expect(viewModel.displaySyncStatus == .pending)
        #expect(!viewModel.showsRetryUpload)
    }

    @Test func displaySyncStatusKeepsUploadingOverRemotePending() async {
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(syncStatus: .uploading),
            currentUserID: Self.mockCurrentUserID,
            service: MockProjectsService(
                projects: [makeProject(syncStatus: .uploading)],
                simulatedDelayNanoseconds: 0
            ),
            scanDetailService: ScanDetailStatusStub(syncStatus: .pending)
        )

        await viewModel.loadDetail()

        #expect(viewModel.displaySyncStatus == .uploading)
    }

    @Test func displaySyncStatusTrustsRemoteSyncedWhenLocalIsPending() async {
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(syncStatus: .pending),
            currentUserID: Self.mockCurrentUserID,
            service: MockProjectsService(
                projects: [makeProject(syncStatus: .pending)],
                simulatedDelayNanoseconds: 0
            ),
            scanDetailService: ScanDetailStatusStub(syncStatus: .synced)
        )

        await viewModel.loadDetail()

        #expect(viewModel.displaySyncStatus == .synced)
        #expect(viewModel.canShare)
        #expect(!viewModel.showsRetryUpload)
    }

    @Test func canShareRequiresSyncedStatus() {
        #expect(makeViewModel(syncStatus: .synced).canShare)
        #expect(!makeViewModel(syncStatus: .pending).canShare)
        #expect(!makeViewModel(syncStatus: .uploading).canShare)
        #expect(!makeViewModel(syncStatus: .failed).canShare)
        #expect(!makeViewModel(syncStatus: .conflict).canShare)
    }

    @Test func canShareWhenPendingScanHasUploadedAssets() {
        #expect(
            makeViewModel(syncStatus: .pending, assetStatus: "UPLOADED").canShare
        )
        #expect(
            makeViewModel(syncStatus: .pending, assetStatus: "READY").canShare
        )
    }

    @Test func retryUploadIgnoredWhenNotFailed() async {
        let viewModel = makeViewModel(syncStatus: .synced)
        let didRetry = await viewModel.retryUpload()
        #expect(!didRetry)
    }

    @Test func readOnlyRenameDoesNotMutateAndReturnsFalse() async {
        let service = MockProjectsService(
            projects: [makeProject()],
            simulatedDelayNanoseconds: 0
        )
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(name: "Living Room"),
            currentUserID: Self.mockCurrentUserID,
            service: service,
            accessPolicy: .readOnly
        )
        viewModel.renameDraft = "Dining Room"

        let didRename = await viewModel.renameScan()

        #expect(!didRename)
        #expect(!viewModel.allowsOwnerActions)
        #expect(!viewModel.showsActionError)
        #expect(viewModel.scan.name == "Living Room")
        #expect(viewModel.title == "Living Room")
    }

    @Test func readOnlyDeleteDoesNotMutateAndReturnsFalse() async {
        let service = MockProjectsService(
            projects: [makeProject()],
            simulatedDelayNanoseconds: 0
        )
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(),
            currentUserID: Self.mockCurrentUserID,
            service: service,
            accessPolicy: .readOnly
        )

        let didDelete = await viewModel.deleteScan()

        #expect(!didDelete)
        #expect(!viewModel.didDeleteScan)
        #expect(!viewModel.showsActionError)
    }

    @Test func readOnlyRetryDoesNotMutateAndReturnsFalse() async {
        let service = MockProjectsService(
            projects: [makeProject(syncStatus: .failed)],
            simulatedDelayNanoseconds: 0
        )
        let viewModel = ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(syncStatus: .failed),
            currentUserID: Self.mockCurrentUserID,
            service: service,
            accessPolicy: .readOnly
        )

        #expect(!viewModel.showsRetryUpload)

        let didRetry = await viewModel.retryUpload()

        #expect(!didRetry)
        #expect(viewModel.scan.syncStatus == .failed)
        #expect(!viewModel.showsActionError)
    }

    private func makeViewModel(
        creatorUserID: String = Self.mockCurrentUserID,
        creatorDisplayName: String = Self.mockCurrentUserDisplayName,
        createdAt: Date = Date(timeIntervalSince1970: 1_781_251_200),
        noteCount: Int = 0,
        syncStatus: RoomScanSyncStatus = .synced,
        assetStatus: String? = nil
    ) -> ScanDetailViewModel {
        ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(
                createdAt: createdAt,
                syncStatus: syncStatus,
                creatorUserID: creatorUserID,
                creatorDisplayName: creatorDisplayName,
                noteCount: noteCount,
                assetStatus: assetStatus
            ),
            currentUserID: Self.mockCurrentUserID,
            service: MockProjectsService(
                projects: [makeProject()],
                simulatedDelayNanoseconds: 0
            )
        )
    }

    private func makeProject(
        syncStatus: RoomScanSyncStatus = .synced,
        roomScans: [RoomScanSummary]? = nil
    ) -> ProjectSummary {
        ProjectSummary(
            id: "project-1",
            name: "Project",
            ownerName: "You",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            description: "",
            sharedUserCount: 0,
            roomScans: roomScans ?? [makeScan(syncStatus: syncStatus)]
        )
    }

    private func makeScan(
        id: String = "scan-1",
        name: String = "Living Room",
        createdAt: Date = Date(timeIntervalSince1970: 1_781_251_200),
        localModelURL: URL? = nil,
        syncStatus: RoomScanSyncStatus = .synced,
        creatorUserID: String = Self.mockCurrentUserID,
        creatorDisplayName: String = Self.mockCurrentUserDisplayName,
        noteCount: Int = 0,
        assetStatus: String? = nil
    ) -> RoomScanSummary {
        RoomScanSummary(
            id: id,
            name: name,
            createdAt: createdAt,
            localModelURL: localModelURL,
            thumbnailName: "thumbnail-0",
            syncStatus: syncStatus,
            creatorUserID: creatorUserID,
            creatorDisplayName: creatorDisplayName,
            notes: (0..<noteCount).map {
                RoomScanNoteSummary(
                    id: "note-\($0)",
                    text: "Note \($0)",
                    createdAt: createdAt
                )
            },
            assetStatus: assetStatus
        )
    }
}

@MainActor
struct ScanDetailAssetAvailabilityTests {
    @Test func remoteModelDownloadRequiresAnAvailableAsset() async {
        let unavailableViewModel = makeViewModel(assetStatus: "NONE")
        let availableViewModel = makeViewModel(assetStatus: "UPLOADED")

        #expect(!unavailableViewModel.canOpen3DModel)
        await unavailableViewModel.loadDetail()
        #expect(!unavailableViewModel.canOpen3DModel)

        await availableViewModel.loadDetail()
        #expect(availableViewModel.canOpen3DModel)
    }

    @Test func viewerModelVersionMatchesScanDetailVersion() async {
        let viewModel = makeViewModel(assetStatus: "UPLOADED")

        await viewModel.loadDetail()

        #expect(viewModel.viewerModelVersion == "1")
    }

    private func makeViewModel(assetStatus: String) -> ScanDetailViewModel {
        ScanDetailViewModel(
            projectID: "project-1",
            scan: RoomScanSummary(
                id: "scan-1",
                name: "Living Room",
                createdAt: .now,
                localModelURL: nil,
                thumbnailName: "thumbnail-0",
                syncStatus: .synced,
                creatorUserID: "mock-user-apple",
                creatorDisplayName: "Mock Apple User",
                notes: []
            ),
            currentUserID: "mock-user-apple",
            service: MockProjectsService(projects: [], simulatedDelayNanoseconds: 0),
            scanDetailService: ScanDetailRenameStub(assetStatus: assetStatus)
        )
    }
}

private struct ScanDetailRenameStub: ScanDetailService {
    let assetStatus: String
    let thumbnail: String?
    let noteCount: Int
    let creatorID: String
    let creatorDisplayName: String?
    let creatorEmail: String?

    init(
        assetStatus: String = "NONE",
        thumbnail: String? = nil,
        noteCount: Int = 0,
        creatorID: String = "mock-user-apple",
        creatorDisplayName: String? = nil,
        creatorEmail: String? = nil
    ) {
        self.assetStatus = assetStatus
        self.thumbnail = thumbnail
        self.noteCount = noteCount
        self.creatorID = creatorID
        self.creatorDisplayName = creatorDisplayName
        self.creatorEmail = creatorEmail
    }

    func fetchScanDetail(id: String) async throws -> ScanDetail {
        makeDetail(id: id, name: "Living Room", description: "")
    }

    func updateScanDetail(id: String, name: String, description: String?) async throws -> ScanDetail {
        makeDetail(id: id, name: name, description: description)
    }

    func deleteScanDetail(id: String) async throws {}

    func makeDetail(id: String, name: String, description: String?) -> ScanDetail {
        ScanDetail(
            id: id,
            projectID: "project-1",
            name: name,
            description: description,
            thumbnail: thumbnail,
            creatorID: creatorID,
            creatorDisplayName: creatorDisplayName,
            creatorEmail: creatorEmail,
            noteCount: noteCount,
            assetStatus: assetStatus,
            syncStatus: .synced,
            modelVersion: 1,
            createdAt: .now,
            updatedAt: .now,
            permissions: ScanDetailPermissions(
                role: "OWNER",
                canView: true,
                canEdit: true,
                canDelete: true
            )
        )
    }
}

private struct DuplicateScanDetailRenameStub: ScanDetailService {
    func fetchScanDetail(id: String) async throws -> ScanDetail {
        ScanDetailRenameStub().makeDetail(id: id, name: "Living Room", description: nil)
    }

    func updateScanDetail(id: String, name: String, description: String?) async throws -> ScanDetail {
        throw HTTPClientError.serverError(statusCode: 409, apiError: nil)
    }

    func deleteScanDetail(id: String) async throws {}
}

private final class ScanDetailNoteCountStub: ScanDetailService, @unchecked Sendable {
    private var remainingCounts: [Int]

    init(noteCounts: [Int]) {
        remainingCounts = noteCounts
    }

    func fetchScanDetail(id: String) async throws -> ScanDetail {
        let count = remainingCounts.isEmpty ? 0 : remainingCounts.removeFirst()
        return ScanDetailRenameStub(noteCount: count).makeDetail(
            id: id,
            name: "Living Room",
            description: nil
        )
    }

    func updateScanDetail(id: String, name: String, description: String?) async throws -> ScanDetail {
        ScanDetailRenameStub().makeDetail(id: id, name: name, description: description)
    }

    func deleteScanDetail(id: String) async throws {}
}

/// Completes the second fetch before releasing the first so callers can verify
/// that a superseded response does not overwrite newer detail state.
private actor ReverseCompletionScanDetailStub: ScanDetailService {
    private let staleNoteCount: Int
    private let latestNoteCount: Int
    private var fetchCount = 0
    private var firstContinuation: CheckedContinuation<ScanDetail, Never>?
    private var firstFetchSuspendedContinuation: CheckedContinuation<Void, Never>?

    init(staleNoteCount: Int, latestNoteCount: Int) {
        self.staleNoteCount = staleNoteCount
        self.latestNoteCount = latestNoteCount
    }

    func waitUntilFirstFetchIsSuspended() async {
        if firstContinuation != nil { return }
        await withCheckedContinuation { continuation in
            firstFetchSuspendedContinuation = continuation
        }
    }

    func fetchScanDetail(id: String) async throws -> ScanDetail {
        fetchCount += 1
        if fetchCount == 1 {
            return await withCheckedContinuation { continuation in
                firstContinuation = continuation
                firstFetchSuspendedContinuation?.resume()
                firstFetchSuspendedContinuation = nil
            }
        }

        let latest = ScanDetailRenameStub(noteCount: latestNoteCount).makeDetail(
            id: id,
            name: "Living Room",
            description: nil
        )
        if let firstContinuation {
            self.firstContinuation = nil
            firstContinuation.resume(
                returning: ScanDetailRenameStub(noteCount: staleNoteCount).makeDetail(
                    id: id,
                    name: "Living Room",
                    description: nil
                )
            )
        }
        return latest
    }

    func updateScanDetail(id: String, name: String, description: String?) async throws -> ScanDetail {
        ScanDetailRenameStub().makeDetail(id: id, name: name, description: description)
    }

    func deleteScanDetail(id: String) async throws {}
}

/// Suspends the first visible fetch, then serves an immediate refreshed payload for a deferred silent load.
private actor DeferredSilentRefreshScanDetailStub: ScanDetailService {
    private let firstNoteCount: Int
    private let refreshedNoteCount: Int
    private var startedFetchCount = 0
    private var firstContinuation: CheckedContinuation<ScanDetail, Never>?
    private var firstFetchSuspendedContinuation: CheckedContinuation<Void, Never>?

    init(firstNoteCount: Int, refreshedNoteCount: Int) {
        self.firstNoteCount = firstNoteCount
        self.refreshedNoteCount = refreshedNoteCount
    }

    func fetchCount() -> Int {
        startedFetchCount
    }

    func waitUntilFirstFetchIsSuspended() async {
        if firstContinuation != nil { return }
        await withCheckedContinuation { continuation in
            firstFetchSuspendedContinuation = continuation
        }
    }

    func releaseFirstFetch() {
        guard let firstContinuation else { return }
        self.firstContinuation = nil
        firstContinuation.resume(
            returning: ScanDetailRenameStub(noteCount: firstNoteCount).makeDetail(
                id: "scan-1",
                name: "Living Room",
                description: nil
            )
        )
    }

    func fetchScanDetail(id: String) async throws -> ScanDetail {
        startedFetchCount += 1
        if startedFetchCount == 1 {
            return await withCheckedContinuation { continuation in
                firstContinuation = continuation
                firstFetchSuspendedContinuation?.resume()
                firstFetchSuspendedContinuation = nil
            }
        }
        return ScanDetailRenameStub(noteCount: refreshedNoteCount).makeDetail(
            id: id,
            name: "Living Room",
            description: nil
        )
    }

    func updateScanDetail(id: String, name: String, description: String?) async throws -> ScanDetail {
        ScanDetailRenameStub().makeDetail(id: id, name: name, description: description)
    }

    func deleteScanDetail(id: String) async throws {}
}

/// Holds a detail fetch until explicitly released so a mutation can win over a stale response.
private actor SuspendedFetchScanDetailStub: ScanDetailService {
    private let staleName: String
    private var fetchContinuation: CheckedContinuation<ScanDetail, Never>?
    private var fetchSuspendedContinuation: CheckedContinuation<Void, Never>?
    private var startedFetchCount = 0

    init(staleName: String) {
        self.staleName = staleName
    }

    func fetchCount() -> Int {
        startedFetchCount
    }

    func waitUntilFetchIsSuspended() async {
        if fetchContinuation != nil { return }
        await withCheckedContinuation { continuation in
            fetchSuspendedContinuation = continuation
        }
    }

    func releaseSuspendedFetch() {
        guard let fetchContinuation else { return }
        self.fetchContinuation = nil
        fetchContinuation.resume(
            returning: ScanDetailRenameStub().makeDetail(
                id: "scan-1",
                name: staleName,
                description: nil
            )
        )
    }

    func fetchScanDetail(id: String) async throws -> ScanDetail {
        startedFetchCount += 1
        return await withCheckedContinuation { continuation in
            fetchContinuation = continuation
            fetchSuspendedContinuation?.resume()
            fetchSuspendedContinuation = nil
        }
    }

    func updateScanDetail(id: String, name: String, description: String?) async throws -> ScanDetail {
        ScanDetailRenameStub().makeDetail(id: id, name: name, description: description)
    }

    func deleteScanDetail(id: String) async throws {}
}

private actor ScanDetailRenameSpy: ScanDetailService {
    private var updateDescription: String?

    func fetchScanDetail(id: String) async throws -> ScanDetail {
        ScanDetailRenameStub().makeDetail(id: id, name: "Living Room", description: nil)
    }

    func updateScanDetail(id: String, name: String, description: String?) async throws -> ScanDetail {
        updateDescription = description
        return ScanDetailRenameStub().makeDetail(id: id, name: name, description: description)
    }

    func deleteScanDetail(id: String) async throws {}

    func lastUpdateDescription() -> String? {
        updateDescription
    }
}

private struct ScanDetailStatusStub: ScanDetailService {
    let syncStatus: RoomScanSyncStatus

    func fetchScanDetail(id: String) async throws -> ScanDetail {
        ScanDetailRenameStub().makeDetail(id: id, name: "Living Room", description: nil)
            .updating(syncStatus: syncStatus)
    }

    func updateScanDetail(id: String, name: String, description: String?) async throws -> ScanDetail {
        ScanDetailRenameStub().makeDetail(id: id, name: name, description: description)
    }

    func deleteScanDetail(id: String) async throws {}
}

private struct ScanDetailRetryStub: ScanDetailService {
    func fetchScanDetail(id: String) async throws -> ScanDetail {
        ScanDetailRenameStub().makeDetail(id: id, name: "Living Room", description: nil)
            .updating(syncStatus: .failed)
    }

    func updateScanDetail(id: String, name: String, description: String?) async throws -> ScanDetail {
        ScanDetailRenameStub().makeDetail(id: id, name: name, description: description)
    }

    func deleteScanDetail(id: String) async throws {}
}
