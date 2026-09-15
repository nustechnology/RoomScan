//
//  InvitationViewModelTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

@MainActor
struct InvitationViewModelTests {
    @Test func loadInvitationPopulatesProjectDetails() async {
        let service = LocalInvitationService(simulatedDelayNanoseconds: 0)
        let viewModel = InvitationViewModel(
            pendingInvitation: PendingInvitation(scope: .project, token: "valid-project"),
            service: service,
            currentUserEmail: "anyone@example.com"
        )

        await viewModel.loadInvitation()

        #expect(viewModel.invitation?.title == "Company Office — Floor 3")
        #expect(viewModel.invitation?.ownerName == "Nguyen Minh Anh")
        #expect(viewModel.invitation?.itemCount == 4)
        #expect(viewModel.blockingAlert == nil)
    }

    @Test func loadInvitationPopulatesScanDetails() async {
        let service = LocalInvitationService(simulatedDelayNanoseconds: 0)
        let viewModel = InvitationViewModel(
            pendingInvitation: PendingInvitation(scope: .scan, token: "valid-scan"),
            service: service,
            currentUserEmail: "anyone@example.com"
        )

        await viewModel.loadInvitation()

        #expect(viewModel.invitation?.title == "Meeting Room 3A")
        #expect(viewModel.invitation?.itemCount == 5)
        #expect(viewModel.screenTitle == String(localized: "invitation.scan.title"))
    }

    @Test func openExistingAccessNavigatesWithoutAcceptingInvitation() async {
        let viewModel = InvitationViewModel(
            pendingInvitation: PendingInvitation(scope: .project, token: "existing-access"),
            service: ExistingAccessInvitationService(),
            currentUserEmail: "viewer@example.com"
        )

        await viewModel.loadInvitation()
        #expect(viewModel.hasExistingAccess)

        viewModel.openExistingAccess()

        guard let outcome = viewModel.navigationOutcome,
              case .opened(.project(let project)) = outcome else {
            Issue.record("Expected existing project access to open directly")
            return
        }
        #expect(project.id == "existing-project")
    }

    @Test func expiredInvitationSurfacesBlockingAlert() async {
        let service = LocalInvitationService(simulatedDelayNanoseconds: 0)
        let viewModel = InvitationViewModel(
            pendingInvitation: PendingInvitation(scope: .project, token: "expired-project"),
            service: service,
            currentUserEmail: nil
        )

        await viewModel.loadInvitation()

        #expect(viewModel.blockingAlert == .expired)
        #expect(viewModel.invitation == nil)
    }

    @Test func acceptedInvitationSurfacesAlreadyAcceptedAlert() async {
        let service = LocalInvitationService(simulatedDelayNanoseconds: 0)
        let viewModel = InvitationViewModel(
            pendingInvitation: PendingInvitation(scope: .project, token: "accepted-project"),
            service: service,
            currentUserEmail: nil
        )

        await viewModel.loadInvitation()

        #expect(viewModel.blockingAlert == .alreadyAccepted)
        #expect(viewModel.invitation == nil)
    }

    @Test func declinedInvitationSurfacesDeclinedAlert() async {
        let service = LocalInvitationService(simulatedDelayNanoseconds: 0)
        let viewModel = InvitationViewModel(
            pendingInvitation: PendingInvitation(scope: .project, token: "declined-project"),
            service: service,
            currentUserEmail: nil
        )

        await viewModel.loadInvitation()

        #expect(viewModel.blockingAlert == .declined)
        #expect(viewModel.invitation == nil)
    }

    @Test func revokedInvitationSurfacesUnavailableAlert() async {
        let service = LocalInvitationService(simulatedDelayNanoseconds: 0)
        let viewModel = InvitationViewModel(
            pendingInvitation: PendingInvitation(scope: .scan, token: "revoked-scan"),
            service: service,
            currentUserEmail: nil
        )

        await viewModel.loadInvitation()

        #expect(viewModel.blockingAlert == .unavailable)
    }

    @Test func mismatchedAccountSurfacesAccessDenied() async {
        let service = LocalInvitationService(simulatedDelayNanoseconds: 0)
        let viewModel = InvitationViewModel(
            pendingInvitation: PendingInvitation(scope: .project, token: "mismatch-project"),
            service: service,
            currentUserEmail: "other@example.com"
        )

        await viewModel.loadInvitation()

        #expect(viewModel.blockingAlert == .accessDenied)
    }

    @Test func acceptProjectNavigatesToProjectDetails() async {
        let service = LocalInvitationService(simulatedDelayNanoseconds: 0)
        let viewModel = InvitationViewModel(
            pendingInvitation: PendingInvitation(scope: .project, token: "valid-project"),
            service: service,
            currentUserEmail: nil
        )

        await viewModel.loadInvitation()
        await viewModel.accept()

        guard let outcome = viewModel.navigationOutcome,
              case .accepted(let destination, let toast) = outcome else {
            Issue.record("Expected accepted navigation outcome")
            return
        }
        #expect(toast == String(localized: "invitation.toast.accepted"))
        guard case .project(let project) = destination else {
            Issue.record("Expected project destination")
            return
        }
        #expect(project.name == "Company Office — Floor 3")
    }

    @Test func acceptScanNavigatesToViewer() async {
        let service = LocalInvitationService(simulatedDelayNanoseconds: 0)
        let viewModel = InvitationViewModel(
            pendingInvitation: PendingInvitation(scope: .scan, token: "valid-scan"),
            service: service,
            currentUserEmail: nil
        )

        await viewModel.loadInvitation()
        await viewModel.accept()

        guard let outcome = viewModel.navigationOutcome,
              case .accepted(let destination, _) = outcome else {
            Issue.record("Expected accepted navigation outcome")
            return
        }
        guard case .scan(let item) = destination else {
            Issue.record("Expected scan destination")
            return
        }
        #expect(item.name == "Meeting Room 3A")
        #expect(item.id == "shared-scan-meeting-3a")
        #expect(item.status == .active)
        #expect(item.detailScan != nil)
    }

    @Test func requestDeclineOnShareLinkDismissesWithoutConfirmation() async {
        let service = LocalInvitationService(simulatedDelayNanoseconds: 0)
        let viewModel = InvitationViewModel(
            pendingInvitation: PendingInvitation(scope: .project, token: "share-link-project"),
            service: service,
            currentUserEmail: nil
        )

        await viewModel.loadInvitation()
        #expect(viewModel.invitation?.type == .shareLink)

        viewModel.requestDecline()

        #expect(viewModel.showsDeclineConfirmation == false)
        guard let outcome = viewModel.navigationOutcome,
              case .dismissedToHome(let toast) = outcome else {
            Issue.record("Expected share-link decline to close the invitation")
            return
        }
        #expect(toast == nil)
    }

    @Test func confirmDeclineReturnsHomeWithToast() async {
        let service = LocalInvitationService(simulatedDelayNanoseconds: 0)
        let viewModel = InvitationViewModel(
            pendingInvitation: PendingInvitation(scope: .project, token: "valid-project"),
            service: service,
            currentUserEmail: nil
        )

        await viewModel.loadInvitation()
        #expect(viewModel.invitation?.type == .invitation)
        viewModel.requestDecline()
        #expect(viewModel.showsDeclineConfirmation)
        await viewModel.confirmDecline()

        guard let outcome = viewModel.navigationOutcome,
              case .dismissedToHome(let toast) = outcome else {
            Issue.record("Expected dismissed navigation outcome")
            return
        }
        #expect(toast == String(localized: "invitation.toast.declined"))
        #expect(viewModel.showsDeclineConfirmation == false)
    }

    @Test func dismissBlockingAlertReturnsHome() async {
        let service = LocalInvitationService(simulatedDelayNanoseconds: 0)
        let viewModel = InvitationViewModel(
            pendingInvitation: PendingInvitation(scope: .project, token: "expired-project"),
            service: service,
            currentUserEmail: nil
        )

        await viewModel.loadInvitation()
        viewModel.dismissBlockingAlert()

        guard let outcome = viewModel.navigationOutcome,
              case .dismissedToHome(let toast) = outcome else {
            Issue.record("Expected dismissed navigation outcome")
            return
        }
        #expect(toast == nil)
        #expect(viewModel.blockingAlert == nil)
    }

    @Test func acceptNetworkFailureSurfacesRetryableActionError() async {
        let service = LocalInvitationService(
            scenario: .networkFailure,
            simulatedDelayNanoseconds: 0
        )
        let viewModel = InvitationViewModel(
            pendingInvitation: PendingInvitation(scope: .project, token: "valid-project"),
            service: service,
            currentUserEmail: nil
        )

        await viewModel.accept()

        #expect(
            viewModel.actionFailure
                == InvitationViewModel.ActionFailure(action: .accept, error: .network)
        )
        #expect(viewModel.navigationOutcome == nil)
    }

    @Test func declineNetworkFailureSurfacesRetryableActionError() async {
        let service = LocalInvitationService(
            scenario: .networkFailure,
            simulatedDelayNanoseconds: 0
        )
        let viewModel = InvitationViewModel(
            pendingInvitation: PendingInvitation(scope: .scan, token: "valid-scan"),
            service: service,
            currentUserEmail: nil
        )

        await viewModel.confirmDecline()

        #expect(
            viewModel.actionFailure
                == InvitationViewModel.ActionFailure(action: .decline, error: .network)
        )
        #expect(viewModel.navigationOutcome == nil)
    }

    @Test func retryFailedAcceptCompletesOriginalAction() async {
        let service = OneTimeFailingInvitationService()
        let viewModel = InvitationViewModel(
            pendingInvitation: PendingInvitation(scope: .scan, token: "valid-scan"),
            service: service,
            currentUserEmail: nil
        )

        await viewModel.accept()
        #expect(viewModel.actionFailure?.action == .accept)

        await viewModel.retryFailedAction(.accept)

        guard case .accepted(.scan(let item), _) = viewModel.navigationOutcome else {
            Issue.record("Expected the retried invitation to be accepted")
            return
        }
        #expect(item.id == "scan-retried")
        #expect(viewModel.actionFailure == nil)
    }
}

struct InvitationDeepLinkParserTests {
    @Test func parsesHTTPSInvite() throws {
        let url = try #require(
            URL(
                string: "https://roomscan.nustechnology.com/invitations/uRly-Hf-plhnjPHkgJ-t9btOXwYTcA9XnH76tDcQRwk"
            )
        )
        let invitation = InvitationDeepLinkParser.parse(url)
        #expect(
            invitation == PendingInvitation(
                scope: .project,
                token: "uRly-Hf-plhnjPHkgJ-t9btOXwYTcA9XnH76tDcQRwk"
            )
        )
    }

    @Test func parsesCustomSchemeInvite() throws {
        let url = try #require(URL(string: "roomscan://invitations/token-1"))
        let invitation = InvitationDeepLinkParser.parse(url)
        #expect(invitation == PendingInvitation(scope: .project, token: "token-1"))
    }

    @Test func parsesScanScopeFromHTTPSInvite() throws {
        let url = try #require(
            URL(string: "https://roomscan.nustechnology.com/invitations/token-1?scope=scan")
        )

        #expect(
            InvitationDeepLinkParser.parse(url)
                == PendingInvitation(scope: .scan, token: "token-1")
        )
    }

    @Test func rejectsUnknownPaths() throws {
        let url = try #require(URL(string: "https://roomscan.nustechnology.com/projects/1"))
        #expect(InvitationDeepLinkParser.parse(url) == nil)
    }

    @Test func rejectsUnknownHost() throws {
        let url = try #require(URL(string: "https://roomscan.app/invitations/token"))
        #expect(InvitationDeepLinkParser.parse(url) == nil)
    }

    @Test func rejectsNonHTTPSWebInvite() throws {
        let url = try #require(URL(string: "http://roomscan.nustechnology.com/invitations/token"))
        #expect(InvitationDeepLinkParser.parse(url) == nil)
    }

    @Test func rejectsWebInviteWithTrailingPath() throws {
        let url = try #require(
            URL(string: "https://roomscan.nustechnology.com/invitations/token/extra")
        )
        #expect(InvitationDeepLinkParser.parse(url) == nil)
    }

    @Test func rejectsCustomInviteWithTrailingPath() throws {
        let url = try #require(URL(string: "roomscan://invitations/token/extra"))
        #expect(InvitationDeepLinkParser.parse(url) == nil)
    }

    @Test func rejectsLegacyCustomInvitePath() throws {
        let url = try #require(URL(string: "roomscan://invite/project/token-1"))
        #expect(InvitationDeepLinkParser.parse(url) == nil)
    }

    @Test func rejectsEncodedPathSeparatorsAndDotSegmentsInToken() throws {
        let urls = [
            "https://roomscan.nustechnology.com/invitations/token%2Fextra",
            "https://roomscan.nustechnology.com/invitations/%2E%2E%2Fprojects",
            "https://roomscan.nustechnology.com/invitations/%2E%2E"
        ]

        for rawURL in urls {
            let url = try #require(URL(string: rawURL))
            #expect(InvitationDeepLinkParser.parse(url) == nil)
        }
    }
}

struct AcceptedInvitationCollectionTests {
    @Test func storesAcceptedDestination() {
        var collection = AcceptedInvitationCollection()
        let destination = AcceptedInvitationDestination.scan(makeAcceptedSharedScan(id: "scan-1", name: "Lobby"))

        collection.store(destination)

        #expect(collection.destinations == [destination])
    }

    @Test func replacesPreviouslyAcceptedDestinationWithSameID() {
        var collection = AcceptedInvitationCollection()
        collection.store(
            .scan(makeAcceptedSharedScan(id: "scan-1", name: "Old Name"))
        )

        let updatedDestination = AcceptedInvitationDestination.scan(
            makeAcceptedSharedScan(id: "scan-1", name: "New Name")
        )
        collection.store(updatedDestination)

        #expect(collection.destinations == [updatedDestination])
    }

    @Test func applyUpdatedScanPersistsRenameForAcceptedProject() {
        var collection = AcceptedInvitationCollection()
        let project = makeAcceptedProject(
            id: "shared-project",
            scans: [
                makeAcceptedScan(id: "scan-1", name: "Living Room"),
                makeAcceptedScan(id: "scan-2", name: "Kitchen")
            ]
        )
        collection.store(.project(project))

        let renamedScan = makeAcceptedScan(id: "scan-1", name: "Front Room")
        collection.applyUpdatedScan(projectID: project.id, scan: renamedScan)

        guard case .project(let reopenedProject) = collection.destinations.first else {
            Issue.record("Expected accepted project destination")
            return
        }
        #expect(reopenedProject.roomScans.map(\.name) == ["Front Room", "Kitchen"])
        #expect(reopenedProject.roomScans.first?.id == "scan-1")
    }

    @Test func applyRenamedScanPersistsRenameForAcceptedScanDestination() {
        var collection = AcceptedInvitationCollection()
        collection.store(
            .scan(makeAcceptedSharedScan(id: "scan-1", name: "Meeting Room 3A"))
        )

        collection.applyRenamedScan(scanID: "scan-1", name: "  Front Desk  ")

        guard case .scan(let item) = collection.destinations.first else {
            Issue.record("Expected accepted scan destination")
            return
        }
        #expect(item.name == "Front Desk")
        #expect(item.id == "scan-1")
        #expect(item.detailScan?.name == "Front Desk")
    }

    @Test func applyRenamedScanIgnoresEmptyNameAndUnknownScan() {
        var collection = AcceptedInvitationCollection()
        let destination = AcceptedInvitationDestination.scan(
            makeAcceptedSharedScan(id: "scan-1", name: "Lobby")
        )
        collection.store(destination)

        collection.applyRenamedScan(scanID: "scan-1", name: "   ")
        collection.applyRenamedScan(scanID: "missing", name: "Renamed")

        #expect(collection.destinations == [destination])
    }

    @Test func applyDeletedScanPersistsRemovalForAcceptedProject() {
        var collection = AcceptedInvitationCollection()
        let project = makeAcceptedProject(
            id: "shared-project",
            scans: [
                makeAcceptedScan(id: "scan-1", name: "Living Room"),
                makeAcceptedScan(id: "scan-2", name: "Kitchen")
            ]
        )
        collection.store(.project(project))

        collection.applyDeletedScan(projectID: project.id, scanID: "scan-1")

        guard case .project(let reopenedProject) = collection.destinations.first else {
            Issue.record("Expected accepted project destination")
            return
        }
        #expect(reopenedProject.roomScans.map(\.id) == ["scan-2"])
        #expect(reopenedProject.roomScans.map(\.name) == ["Kitchen"])
    }

    @Test func applyUpdatedScanLeavesUnrelatedDestinationsUnchanged() {
        var collection = AcceptedInvitationCollection()
        let project = makeAcceptedProject(
            id: "shared-project",
            scans: [makeAcceptedScan(id: "scan-1", name: "Living Room")]
        )
        let scanDestination = AcceptedInvitationDestination.scan(
            makeAcceptedSharedScan(id: "other-scan", name: "Lobby")
        )
        collection.store(.project(project))
        collection.store(scanDestination)

        collection.applyUpdatedScan(
            projectID: "missing-project",
            scan: makeAcceptedScan(id: "scan-1", name: "Renamed")
        )

        #expect(collection.destinations.count == 2)
        guard case .project(let storedProject) = collection.destinations[0] else {
            Issue.record("Expected accepted project destination")
            return
        }
        #expect(storedProject.roomScans.map(\.name) == ["Living Room"])
        #expect(collection.destinations[1] == scanDestination)
    }

    @Test func applyDeletedScanLeavesUnrelatedDestinationsUnchanged() {
        var collection = AcceptedInvitationCollection()
        let project = makeAcceptedProject(
            id: "shared-project",
            scans: [makeAcceptedScan(id: "scan-1", name: "Living Room")]
        )
        collection.store(.project(project))
        collection.store(
            .scan(makeAcceptedSharedScan(id: "other-scan", name: "Lobby"))
        )

        collection.applyDeletedScan(projectID: "missing-project", scanID: "scan-1")

        guard case .project(let storedProject) = collection.destinations[0] else {
            Issue.record("Expected accepted project destination")
            return
        }
        #expect(storedProject.roomScans.map(\.id) == ["scan-1"])
        #expect(collection.destinations.count == 2)
    }

    private func makeAcceptedProject(id: String, scans: [RoomScanSummary]) -> ProjectSummary {
        ProjectSummary(
            id: id,
            name: "Shared Project",
            ownerName: "Owner",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            description: "Shared via invitation",
            sharedUserCount: 1,
            roomScans: scans
        )
    }

    private func makeAcceptedScan(id: String, name: String) -> RoomScanSummary {
        RoomScanSummary(
            id: id,
            name: name,
            createdAt: Date(timeIntervalSince1970: 1_500),
            localModelURL: nil,
            thumbnailName: "thumbnail",
            syncStatus: .synced,
            creatorUserID: "owner-1",
            creatorDisplayName: "Owner",
            notes: []
        )
    }

    private func makeAcceptedSharedScan(id: String, name: String) -> SharedScanItem {
        SharedScanItem.make(
            from: makeAcceptedScan(id: id, name: name),
            parent: SharedScanParent(
                ownerName: "Owner",
                projectID: "shared-project",
                projectName: "Shared Project"
            ),
            status: .active,
            statusChangedAt: Date(timeIntervalSince1970: 1_500)
        )
    }
}

private actor ExistingAccessInvitationService: InvitationService {
    func fetchInvitation(
        scope _: InvitationScope,
        token: String,
        currentUserEmail _: String?
    ) async throws -> InvitationDetails {
        let project = ProjectSummary(
            id: "existing-project",
            name: "Existing Project",
            ownerName: "owner@example.com",
            description: "",
            sharedUserCount: 1,
            scanCount: 0
        )
        return InvitationDetails(
            token: token,
            scope: .project,
            type: .invitation,
            title: project.name,
            ownerName: project.ownerName,
            invitedEmail: nil,
            existingAccessDestination: .project(project),
            itemCount: 0,
            showsThumbnail: false,
            project: project,
            scan: nil
        )
    }

    func acceptInvitation(
        scope _: InvitationScope,
        token _: String,
        currentUserEmail _: String?
    ) async throws -> AcceptedInvitationDestination {
        throw InvitationServiceError.unavailable
    }

    func declineInvitation(
        scope _: InvitationScope,
        token _: String,
        currentUserEmail _: String?
    ) async throws {}
}

private actor OneTimeFailingInvitationService: InvitationService {
    private var shouldFailAccept = true

    func fetchInvitation(
        scope: InvitationScope,
        token: String,
        currentUserEmail: String?
    ) async throws -> InvitationDetails {
        throw InvitationServiceError.notFound
    }

    func acceptInvitation(
        scope: InvitationScope,
        token: String,
        currentUserEmail: String?
    ) async throws -> AcceptedInvitationDestination {
        if shouldFailAccept {
            shouldFailAccept = false
            throw InvitationServiceError.network
        }

        return .scan(
            SharedScanItem.make(
                from: RoomScanSummary(
                    id: "scan-retried",
                    name: "Retried Scan",
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
        )
    }

    func declineInvitation(
        scope: InvitationScope,
        token: String,
        currentUserEmail: String?
    ) async throws {}
}
