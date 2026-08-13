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

    @Test func formattedDateUsesMonthDayYear() {
        let viewModel = makeViewModel(
            createdAt: Date(timeIntervalSince1970: 1_781_251_200) // Jun 12, 2026 UTC
        )

        #expect(
            ScanDetailViewModel.formattedDate(
                for: viewModel.scan.createdAt,
                locale: Locale(identifier: "en_US_POSIX"),
                timeZone: TimeZone(secondsFromGMT: 0)!
            ) == "Jun 12, 2026"
        )
    }

    @Test func notesCountTextUsesNoteCount() {
        let viewModel = makeViewModel(noteCount: 3)
        #expect(viewModel.notesCountText == "3")
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
        syncStatus: RoomScanSyncStatus = .synced
    ) -> ScanDetailViewModel {
        ScanDetailViewModel(
            projectID: "project-1",
            scan: makeScan(
                createdAt: createdAt,
                syncStatus: syncStatus,
                creatorUserID: creatorUserID,
                creatorDisplayName: creatorDisplayName,
                noteCount: noteCount
            ),
            currentUserID: Self.mockCurrentUserID,
            service: MockProjectsService(
                projects: [makeProject()],
                simulatedDelayNanoseconds: 0
            )
        )
    }

    private func makeProject(
        syncStatus: RoomScanSyncStatus = .synced
    ) -> ProjectSummary {
        ProjectSummary(
            id: "project-1",
            name: "Project",
            ownerName: "You",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            description: "",
            sharedUserCount: 0,
            roomScans: [makeScan(syncStatus: syncStatus)]
        )
    }

    private func makeScan(
        name: String = "Living Room",
        createdAt: Date = Date(timeIntervalSince1970: 1_781_251_200),
        localModelURL: URL? = nil,
        syncStatus: RoomScanSyncStatus = .synced,
        creatorUserID: String = Self.mockCurrentUserID,
        creatorDisplayName: String = Self.mockCurrentUserDisplayName,
        noteCount: Int = 0
    ) -> RoomScanSummary {
        RoomScanSummary(
            id: "scan-1",
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
            }
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

    init(assetStatus: String = "NONE") {
        self.assetStatus = assetStatus
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
            thumbnail: nil,
            creatorID: "mock-user-apple",
            creatorEmail: nil,
            noteCount: 0,
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
