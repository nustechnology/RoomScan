//
//  ShareHomeViewModelTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

@MainActor
struct ShareHomeViewModelTests {
    @Test func loadsActiveSharedDestinationsOnly() async {
        let now = Date()
        let service = MockSharedService(
            projects: MockSharedService.makeSeedProjects(now: now),
            scans: MockSharedService.makeSeedScans(now: now),
            simulatedDelayNanoseconds: 0,
            now: now
        )
        let viewModel = ShareHomeViewModel(service: service)

        await viewModel.loadIfNeeded()

        #expect(viewModel.viewState == .loaded)
        let ids = Set(viewModel.sharedDestinations.map(\.id))
        #expect(ids.contains("project-shared-project-active"))
        #expect(ids.contains("scan-shared-scan-active"))
        #expect(ids.contains("project-shared-project-revoked") == false)
        #expect(ids.contains("scan-shared-scan-revoked") == false)
        #expect(ids.contains("project-shared-project-expired") == false)
    }

    @Test func emptyServiceProducesEmptyState() async {
        let service = MockSharedService(scenario: .empty, simulatedDelayNanoseconds: 0)
        let viewModel = ShareHomeViewModel(service: service)

        await viewModel.loadIfNeeded()

        #expect(viewModel.viewState == .empty)
        #expect(viewModel.sharedDestinations.isEmpty)
    }

    @Test func failedLoadProducesFailedState() async {
        let service = MockSharedService(scenario: .failLoad, simulatedDelayNanoseconds: 0)
        let viewModel = ShareHomeViewModel(service: service)

        await viewModel.loadIfNeeded()

        #expect(viewModel.viewState == .failed)
        #expect(viewModel.sharedDestinations.isEmpty)
    }

    @Test func refreshReloadsSharedDestinations() async {
        let service = MockSharedService(scenario: .empty, simulatedDelayNanoseconds: 0)
        let viewModel = ShareHomeViewModel(service: service)
        await viewModel.loadIfNeeded()
        #expect(viewModel.viewState == .empty)

        await service.setScenario(.success)
        await viewModel.refresh()

        #expect(viewModel.viewState == .loaded)
        #expect(viewModel.sharedDestinations.isEmpty == false)
    }

    @Test func mergePrefersAcceptedOverSharedDuplicates() {
        let sharedProject = AcceptedInvitationDestination.project(
            ProjectSummary(
                id: "p1",
                name: "Shared Name",
                ownerName: "Owner",
                createdAt: Date(),
                updatedAt: Date(),
                description: "",
                sharedUserCount: 1,
                roomScans: []
            )
        )
        let acceptedProject = AcceptedInvitationDestination.project(
            ProjectSummary(
                id: "p1",
                name: "Accepted Name",
                ownerName: "Owner",
                createdAt: Date(),
                updatedAt: Date(),
                description: "",
                sharedUserCount: 1,
                roomScans: []
            )
        )
        let sharedScan = AcceptedInvitationDestination.scan(
            ViewerInput(scanID: "s1", scanName: "Shared Scan", modelURL: nil)
        )

        let merged = ShareHomeViewModel.merge(
            shared: [sharedProject, sharedScan],
            accepted: [acceptedProject]
        )

        #expect(merged.count == 2)
        #expect(merged[0].id == "project-p1")
        if case .project(let project) = merged[0] {
            #expect(project.name == "Accepted Name")
        } else {
            Issue.record("Expected accepted project first")
        }
        #expect(merged[1].id == "scan-s1")
    }

    @Test func loadIfNeededDoesNotReloadWhenAlreadyLoaded() async {
        let service = MockSharedService(simulatedDelayNanoseconds: 0)
        let viewModel = ShareHomeViewModel(service: service)

        await viewModel.loadIfNeeded()
        let first = viewModel.sharedDestinations
        await viewModel.loadIfNeeded()

        #expect(viewModel.sharedDestinations == first)
    }

    @Test func activeProjectWithoutDetailIsOmitted() {
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

        let destinations = ShareHomeViewModel.destinations(
            fromProjects: [activeWithoutDetail],
            scans: []
        )

        #expect(destinations.isEmpty)
    }
}
