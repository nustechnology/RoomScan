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

    @Test func revokedInvitationSurfacesUnavailableAlert() async {
        let service = LocalInvitationService(simulatedDelayNanoseconds: 0)
        let viewModel = InvitationViewModel(
            pendingInvitation: PendingInvitation(scope: .scan, token: "revoked-scan"),
            service: service,
            currentUserEmail: nil
        )

        await viewModel.loadInvitation()

        #expect(viewModel.blockingAlert == .unavailable(.scan))
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
        guard case .scan(let input) = destination else {
            Issue.record("Expected scan destination")
            return
        }
        #expect(input.scanName == "Meeting Room 3A")
    }

    @Test func confirmDeclineReturnsHomeWithToast() async {
        let service = LocalInvitationService(simulatedDelayNanoseconds: 0)
        let viewModel = InvitationViewModel(
            pendingInvitation: PendingInvitation(scope: .project, token: "valid-project"),
            service: service,
            currentUserEmail: nil
        )

        await viewModel.loadInvitation()
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
        #expect(toast.isEmpty)
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

        guard case .accepted(.scan(let input), _) = viewModel.navigationOutcome else {
            Issue.record("Expected the retried invitation to be accepted")
            return
        }
        #expect(input.scanID == "scan-retried")
        #expect(viewModel.actionFailure == nil)
    }
}

struct InvitationDeepLinkParserTests {
    @Test func parsesHTTPSProjectInvite() throws {
        let url = try #require(URL(string: "https://roomscan.app/invite/project/abc-123"))
        let invitation = InvitationDeepLinkParser.parse(url)
        #expect(invitation == PendingInvitation(scope: .project, token: "abc-123"))
    }

    @Test func parsesHTTPSScanInvite() throws {
        let url = try #require(URL(string: "https://www.roomscan.app/invite/scan/tok-9"))
        let invitation = InvitationDeepLinkParser.parse(url)
        #expect(invitation == PendingInvitation(scope: .scan, token: "tok-9"))
    }

    @Test func parsesCustomSchemeInvite() throws {
        let url = try #require(URL(string: "roomscan://invite/project/token-1"))
        let invitation = InvitationDeepLinkParser.parse(url)
        #expect(invitation == PendingInvitation(scope: .project, token: "token-1"))
    }

    @Test func rejectsUnknownPaths() throws {
        let url = try #require(URL(string: "https://roomscan.app/projects/1"))
        #expect(InvitationDeepLinkParser.parse(url) == nil)
    }

    @Test func rejectsNonHTTPSWebInvite() throws {
        let url = try #require(URL(string: "http://roomscan.app/invite/project/token"))
        #expect(InvitationDeepLinkParser.parse(url) == nil)
    }

    @Test func rejectsWebInviteWithTrailingPath() throws {
        let url = try #require(URL(string: "https://roomscan.app/invite/project/token/extra"))
        #expect(InvitationDeepLinkParser.parse(url) == nil)
    }

    @Test func rejectsCustomInviteWithTrailingPath() throws {
        let url = try #require(URL(string: "roomscan://invite/scan/token/extra"))
        #expect(InvitationDeepLinkParser.parse(url) == nil)
    }
}

struct AcceptedInvitationCollectionTests {
    @Test func storesAcceptedDestination() {
        var collection = AcceptedInvitationCollection()
        let destination = AcceptedInvitationDestination.scan(
            ViewerInput(scanID: "scan-1", scanName: "Lobby", modelURL: nil)
        )

        collection.store(destination)

        #expect(collection.destinations == [destination])
    }

    @Test func replacesPreviouslyAcceptedDestinationWithSameID() {
        var collection = AcceptedInvitationCollection()
        collection.store(
            .scan(ViewerInput(scanID: "scan-1", scanName: "Old Name", modelURL: nil))
        )

        let updatedDestination = AcceptedInvitationDestination.scan(
            ViewerInput(scanID: "scan-1", scanName: "New Name", modelURL: nil)
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
            .scan(ViewerInput(scanID: "scan-1", scanName: "Meeting Room 3A", modelURL: nil))
        )

        collection.applyRenamedScan(scanID: "scan-1", name: "  Front Desk  ")

        guard case .scan(let input) = collection.destinations.first else {
            Issue.record("Expected accepted scan destination")
            return
        }
        #expect(input.scanName == "Front Desk")
        #expect(input.scanID == "scan-1")
    }

    @Test func applyRenamedScanIgnoresEmptyNameAndUnknownScan() {
        var collection = AcceptedInvitationCollection()
        let destination = AcceptedInvitationDestination.scan(
            ViewerInput(scanID: "scan-1", scanName: "Lobby", modelURL: nil)
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
            ViewerInput(scanID: "other-scan", scanName: "Lobby", modelURL: nil)
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
            .scan(ViewerInput(scanID: "other-scan", scanName: "Lobby", modelURL: nil))
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
            ViewerInput(
                scanID: "scan-retried",
                scanName: "Retried Scan",
                modelURL: nil
            )
        )
    }

    func declineInvitation(
        scope: InvitationScope,
        token: String
    ) async throws {}
}
