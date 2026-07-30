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
            service: service
        )
        viewModel.renameDraft = "  Dining Room  "

        let didRename = await viewModel.renameScan()

        #expect(didRename)
        #expect(viewModel.title == "Dining Room")
        #expect(viewModel.scan.name == "Dining Room")
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

    @Test func deleteScanMarksDeletion() async {
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

        #expect(didDelete)
        #expect(viewModel.didDeleteScan)
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

    @Test func retryUploadIgnoredWhenNotFailed() async {
        let viewModel = makeViewModel(syncStatus: .synced)
        let didRetry = await viewModel.retryUpload()
        #expect(!didRetry)
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
