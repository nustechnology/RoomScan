//
//  ShareViewModelTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

@MainActor
struct ShareViewModelTests {
    @Test func initialLoadPopulatesMembers() async {
        let service = TestShareService()
        let viewModel = ShareViewModel(input: .project(id: "project-1", name: "Project", hasUploadedScan: true), service: service)

        await viewModel.loadIfNeeded()

        #expect(viewModel.viewState == .loaded)
        #expect(viewModel.members.count == 2)
        #expect(viewModel.isOffline == false)
    }

    @Test func emptyLoadSetsEmptyState() async {
        let service = TestShareService(members: [])
        let viewModel = ShareViewModel(input: .project(id: "project-1", name: "Project", hasUploadedScan: true), service: service)

        await viewModel.loadIfNeeded()

        #expect(viewModel.viewState == .empty)
        #expect(viewModel.members.isEmpty)
    }

    @Test func duplicateUserIDShowsInlineValidation() async {
        let service = TestShareService()
        let viewModel = ShareViewModel(input: .project(id: "project-1", name: "Project", hasUploadedScan: true), service: service)
        await viewModel.loadIfNeeded()

        viewModel.updateInviteUserID("morgan1234")
        await viewModel.sendInvite()

        #expect(viewModel.userIDValidationMessage == String(localized: "share.validation.userId.duplicate"))
        #expect(viewModel.members.count == 2)
    }

    @Test func blankUserIDShowsRequiredValidationWithoutSending() async {
        let service = TestShareService()
        let viewModel = ShareViewModel(input: .project(id: "project-1", name: "Project", hasUploadedScan: true), service: service)
        await viewModel.loadIfNeeded()

        viewModel.openInviteSheet()
        viewModel.updateInviteUserID("   ")
        await viewModel.sendInvite()

        #expect(viewModel.userIDValidationMessage == String(localized: "share.validation.userId.required"))
        #expect(await service.sentUserIDs().isEmpty)
    }

    @Test(arguments: zip(
        [ShareServiceError.recipientNotFound, .invalidRecipient, .cannotInviteSelf],
        ["share.validation.userId.notFound", "share.validation.userId.invalid", "share.validation.userId.self"]
    ))
    func recipientErrorsShowInlineAndKeepSheetOpen(error: ShareServiceError, messageKey: String) async {
        let service = TestShareService()
        await service.setSendError(error)
        let viewModel = ShareViewModel(input: .project(id: "project-1", name: "Project", hasUploadedScan: true), service: service)
        await viewModel.loadIfNeeded()

        viewModel.openInviteSheet()
        viewModel.updateInviteUserID("ABCDE12345")
        await viewModel.sendInvite()

        #expect(viewModel.userIDValidationMessage == String(localized: String.LocalizationValue(messageKey)))
        #expect(viewModel.isInviteSheetPresented)
        #expect(viewModel.toastMessage == nil)
        #expect(viewModel.members.count == 2)
    }

    @Test func sendInviteAddsPendingMemberAndClosesSheet() async {
        let service = TestShareService()
        let viewModel = ShareViewModel(input: .project(id: "project-1", name: "Project", hasUploadedScan: true), service: service)
        await viewModel.loadIfNeeded()

        viewModel.openInviteSheet()
        viewModel.updateInviteUserID("  NEWUSER123 ")
        await viewModel.sendInvite()

        #expect(await service.sentUserIDs() == ["NEWUSER123"])
        #expect(viewModel.members.count == 3)
        #expect(viewModel.members.first?.publicUserId == "NEWUSER123")
        #expect(viewModel.members.first?.email == nil)
        #expect(viewModel.members.first?.status == .pending)
        #expect(viewModel.isInviteSheetPresented == false)
        #expect(viewModel.toastStyle == .success)
        #expect(viewModel.toastMessage == String(localized: "share.toast.invitationSent"))
    }

    @Test func sendInviteReloadsMembersToPickUpDisplayName() async {
        let service = TestShareService()
        let viewModel = ShareViewModel(input: .project(id: "project-1", name: "Project", hasUploadedScan: true), service: service)
        await viewModel.loadIfNeeded()

        viewModel.openInviteSheet()
        viewModel.updateInviteUserID("NEWUSER123")
        await viewModel.sendInvite()

        #expect(viewModel.members.first?.displayName == TestShareService.listedDisplayName)
        #expect(viewModel.members.first?.rowTitle == TestShareService.listedDisplayName)
    }

    @Test func resendKeepsDisplayNameMissingFromResponse() async throws {
        let service = TestShareService()
        let viewModel = ShareViewModel(input: .project(id: "project-1", name: "Project", hasUploadedScan: true), service: service)
        await viewModel.loadIfNeeded()
        let member = try #require(viewModel.members.first(where: { $0.status == .pending }))

        await viewModel.resendInvitation(for: member)

        let updated = try #require(viewModel.members.first(where: { $0.id == member.id }))
        #expect(updated.displayName == "Morgan Lee")
        #expect(updated.publicUserId == "MORGAN1234")
        #expect(updated.initials == member.initials)
        #expect(updated.publicUserIdLabel != nil)
    }

    @Test func resendUpdatesSentDate() async throws {
        let service = TestShareService()
        let viewModel = ShareViewModel(input: .project(id: "project-1", name: "Project", hasUploadedScan: true), service: service)
        await viewModel.loadIfNeeded()
        let member = try #require(viewModel.members.first(where: { $0.status == .pending }))
        let originalDate = member.sentAt

        await service.setResendDate(Date(timeIntervalSince1970: 1_785_024_000))
        await viewModel.resendInvitation(for: member)

        let updated = try #require(viewModel.members.first(where: { $0.id == member.id }))
        #expect(updated.sentAt == Date(timeIntervalSince1970: 1_785_024_000))
        #expect(updated.sentAt != originalDate)
        #expect(viewModel.toastStyle == .success)
        #expect(
            viewModel.toastMessage == String.localizedStringWithFormat(
                String(localized: "share.toast.invitationResent.format"),
                member.rowTitle
            )
        )
        #expect(viewModel.performingMemberAction == nil)
    }

    @Test func resendReplacesMemberWhenServiceReturnsANewInvitationID() async throws {
        let service = TestShareService()
        let viewModel = ShareViewModel(input: .project(id: "project-1", name: "Project", hasUploadedScan: true), service: service)
        await viewModel.loadIfNeeded()
        let member = try #require(viewModel.members.first(where: { $0.status == .pending }))
        await service.setReplacementInvitationID("pending-2")

        await viewModel.resendInvitation(for: member)

        let replacement = try #require(viewModel.members.first(where: { $0.id == "pending-2" }))
        #expect(viewModel.members.contains(where: { $0.id == member.id }) == false)

        await viewModel.cancelInvitation(for: replacement)

        #expect(await service.revokedInvitationIDs() == ["pending-2"])
    }

    @Test func cancelInvitationRemovesPendingMember() async throws {
        let service = TestShareService()
        let viewModel = ShareViewModel(input: .project(id: "project-1", name: "Project", hasUploadedScan: true), service: service)
        await viewModel.loadIfNeeded()
        let member = try #require(viewModel.members.first(where: { $0.status == .pending }))

        await viewModel.cancelInvitation(for: member)

        #expect(viewModel.members.count == 1)
        #expect(viewModel.members.contains(where: { $0.id == member.id }) == false)
        #expect(viewModel.toastStyle == .success)
        #expect(viewModel.toastMessage == String(localized: "share.toast.invitationCancelled"))
        #expect(viewModel.performingMemberAction == nil)
    }

    @Test func memberActionShowsBusyStateUntilServiceReturns() async throws {
        let service = TestShareService()
        await service.enableActionGate()
        let viewModel = ShareViewModel(input: .project(id: "project-1", name: "Project", hasUploadedScan: true), service: service)
        await viewModel.loadIfNeeded()
        let member = try #require(viewModel.members.first(where: { $0.status == .pending }))
        viewModel.presentActions(for: member)

        let task = Task {
            await viewModel.resendInvitation(for: member)
        }
        await service.waitUntilActionStarts()

        #expect(viewModel.performingMemberAction == .resendInvitation)
        #expect(viewModel.selectedMember?.id == member.id)

        viewModel.dismissActions()
        #expect(viewModel.selectedMember?.id == member.id)

        await service.releaseActionGate()
        await task.value

        #expect(viewModel.performingMemberAction == nil)
        #expect(viewModel.selectedMember == nil)
    }

    @Test func offlineDisablesInviteAndShowsOfflineToast() async {
        let service = TestShareService(isOffline: true)
        let viewModel = ShareViewModel(
            input: .project(id: "project-1", name: "Project", hasUploadedScan: true),
            service: service
        )

        await viewModel.loadIfNeeded()
        viewModel.openInviteSheet()

        #expect(viewModel.isOffline)
        #expect(viewModel.isShareReady == true)
        #expect(viewModel.canInvitePeople == false)
        #expect(viewModel.isInviteSheetPresented == false)
        #expect(viewModel.toastStyle == .error)
        #expect(viewModel.toastMessage == String(localized: "share.error.offline"))
    }

    @Test func projectEnablesInviteWhenItHasAnUploadedScan() async {
        let viewModel = ShareViewModel(
            input: .project(id: "project-1", name: "Project", hasUploadedScan: true),
            service: TestShareService()
        )

        await viewModel.loadIfNeeded()

        #expect(viewModel.isShareReady == true)
        #expect(viewModel.canInvitePeople == true)
    }

    @Test func projectWithoutUploadedScanDisablesInvite() async {
        let viewModel = ShareViewModel(
            input: .project(id: "project-1", name: "Project", hasUploadedScan: false),
            service: TestShareService()
        )

        await viewModel.loadIfNeeded()
        viewModel.openInviteSheet()

        #expect(viewModel.isOffline == false)
        #expect(viewModel.isShareReady == false)
        #expect(viewModel.canInvitePeople == false)
        #expect(viewModel.isInviteSheetPresented == false)
        #expect(viewModel.toastStyle == .error)
        #expect(viewModel.toastMessage == String(localized: "share.error.syncNotReady"))
    }

    @Test func pendingScanDisablesInviteAndShowsSyncToast() async {
        let viewModel = ShareViewModel(
            input: .scan(
                projectID: "project-1",
                projectName: "Project",
                scanID: "scan-1",
                scanName: "Scan",
                syncStatus: .pending
            ),
            service: TestShareService()
        )

        await viewModel.loadIfNeeded()
        viewModel.openInviteSheet()

        #expect(viewModel.isOffline == false)
        #expect(viewModel.isShareReady == false)
        #expect(viewModel.canInvitePeople == false)
        #expect(viewModel.isInviteSheetPresented == false)
        #expect(viewModel.toastStyle == .error)
        #expect(viewModel.toastMessage == String(localized: "share.error.syncNotReady"))
    }

    @Test func uploadingScanDisablesInvite() async {
        let viewModel = ShareViewModel(
            input: .scan(
                projectID: "project-1",
                projectName: "Project",
                scanID: "scan-1",
                scanName: "Scan",
                syncStatus: .uploading
            ),
            service: TestShareService()
        )

        await viewModel.loadIfNeeded()

        #expect(viewModel.isShareReady == false)
        #expect(viewModel.canInvitePeople == false)
    }

    @Test func syncedScanEnablesInvite() async {
        let viewModel = ShareViewModel(
            input: .scan(
                projectID: "project-1",
                projectName: "Project",
                scanID: "scan-1",
                scanName: "Scan",
                syncStatus: .synced
            ),
            service: TestShareService()
        )

        await viewModel.loadIfNeeded()

        #expect(viewModel.isShareReady == true)
        #expect(viewModel.canInvitePeople == true)
    }

    @Test func pendingScanWithUploadedAssetsEnablesInvite() async {
        let viewModel = ShareViewModel(
            input: .scan(
                projectID: "project-1",
                projectName: "Project",
                scanID: "scan-1",
                scanName: "Scan",
                syncStatus: .pending,
                assetStatus: "UPLOADED"
            ),
            service: TestShareService()
        )

        await viewModel.loadIfNeeded()

        #expect(viewModel.isShareReady == true)
        #expect(viewModel.canInvitePeople == true)
    }
}

/// Mirrors the real API: create and resend responses carry no display name,
/// while the shares list does.
actor TestShareService: ShareService {
    static let listedDisplayName = "New Person"

    private var members: [InvitedMember]
    private var isOffline: Bool
    private var resendDate: Date
    private var replacementInvitationID: String?
    private var sendError: ShareServiceError?
    private var sentUserIDValues: [String] = []
    private var revokedInvitationIDValues: [String] = []
    private var isActionGated = false
    private var isWaitingAtGate = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var gateWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        members: [InvitedMember] = [
            InvitedMember(
                id: "accepted-1",
                displayName: "Avery Stone",
                email: "avery@example.com",
                publicUserId: "AVERYSTONE",
                initials: "AS",
                status: .accepted,
                sentAt: Date(timeIntervalSince1970: 1_780_531_200),
                acceptedAt: Date(timeIntervalSince1970: 1_780_876_800)
            ),
            InvitedMember(
                id: "pending-1",
                displayName: "Morgan Lee",
                email: nil,
                publicUserId: "MORGAN1234",
                initials: "ML",
                status: .pending,
                sentAt: Date(timeIntervalSince1970: 1_784_073_600),
                acceptedAt: nil
            )
        ],
        isOffline: Bool = false
    ) {
        self.members = members
        self.isOffline = isOffline
        self.resendDate = Date(timeIntervalSince1970: 1_784_160_000)
    }

    func setResendDate(_ date: Date) {
        resendDate = date
    }

    func setReplacementInvitationID(_ id: String?) {
        replacementInvitationID = id
    }

    func setSendError(_ error: ShareServiceError?) {
        sendError = error
    }

    func sentUserIDs() -> [String] {
        sentUserIDValues
    }

    func revokedInvitationIDs() -> [String] {
        revokedInvitationIDValues
    }

    func enableActionGate() {
        isActionGated = true
    }

    func waitUntilActionStarts() async {
        if isWaitingAtGate { return }
        await withCheckedContinuation { continuation in
            startedWaiters.append(continuation)
        }
    }

    func releaseActionGate() {
        isActionGated = false
        let waiters = gateWaiters
        gateWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func loadInvitedMembers(for input: ShareScreenInput) async throws -> ShareMembersSnapshot {
        ShareMembersSnapshot(members: members, isOffline: isOffline)
    }

    func sendInvitation(for input: ShareScreenInput, publicUserID: String) async throws -> InvitedMember {
        try ensureOnline()
        sentUserIDValues.append(publicUserID)
        if let sendError {
            throw sendError
        }

        if members.contains(where: {
            $0.publicUserId?.caseInsensitiveCompare(publicUserID) == .orderedSame
        }) {
            throw ShareServiceError.duplicateRecipient
        }

        let id = "pending-\(members.count + 1)"
        let sentAt = Date(timeIntervalSince1970: 1_784_246_400)
        members.insert(
            InvitedMember(
                id: id,
                displayName: Self.listedDisplayName,
                email: nil,
                publicUserId: publicUserID,
                initials: "NP",
                status: .pending,
                sentAt: sentAt,
                acceptedAt: nil
            ),
            at: 0
        )
        return InvitedMember(
            id: id,
            displayName: nil,
            email: nil,
            publicUserId: publicUserID,
            initials: String(publicUserID.prefix(2)),
            status: .pending,
            sentAt: sentAt,
            acceptedAt: nil
        )
    }

    func resendInvitation(for input: ShareScreenInput, id: String) async throws -> InvitedMember {
        try await waitAtGateIfNeeded()
        try ensureOnline()
        guard let index = members.firstIndex(where: { $0.id == id }) else {
            throw ShareServiceError.memberNotFound
        }

        let current = members[index]
        let updated = InvitedMember(
            id: replacementInvitationID ?? current.id,
            displayName: nil,
            email: current.email,
            publicUserId: current.publicUserId,
            initials: current.publicUserId.map { String($0.prefix(2)) } ?? "?",
            status: .pending,
            sentAt: resendDate,
            acceptedAt: nil
        )
        members[index] = updated
        return updated
    }

    func revokeInvitation(for input: ShareScreenInput, id: String) async throws {
        try await waitAtGateIfNeeded()
        try ensureOnline()
        revokedInvitationIDValues.append(id)
        members.removeAll { $0.id == id }
    }

    func revokeAccess(for input: ShareScreenInput, userID: String) async throws {
        try await waitAtGateIfNeeded()
        try ensureOnline()
        members.removeAll { $0.id == userID }
    }

    func copyInvitationLink(for input: ShareScreenInput) async throws -> URL {
        try ensureOnline()
        return URL(string: "https://roomscan.app/share/\(input.id)")!
    }

    private func waitAtGateIfNeeded() async {
        guard isActionGated else { return }
        isWaitingAtGate = true
        let waiters = startedWaiters
        startedWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            gateWaiters.append(continuation)
        }
        isWaitingAtGate = false
    }

    private func ensureOnline() throws {
        if isOffline {
            throw ShareServiceError.offline
        }
    }
}
