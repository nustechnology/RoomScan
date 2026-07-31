//
//  ShareHomeViewModel.swift
//  roomscan
//

import Foundation
import Observation

@MainActor
@Observable
final class ShareHomeViewModel {
    enum ViewState: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case failed
    }

    private let service: any SharedService
    private var requestGeneration = 0

    private(set) var viewState: ViewState = .idle
    private(set) var sharedDestinations: [AcceptedInvitationDestination] = []

    init(service: any SharedService) {
        self.service = service
    }

    func loadIfNeeded() async {
        guard viewState == .idle else { return }
        await reload()
    }

    func refresh() async {
        await reload()
    }

    func destinations(merging accepted: [AcceptedInvitationDestination]) -> [AcceptedInvitationDestination] {
        Self.merge(shared: sharedDestinations, accepted: accepted)
    }

    nonisolated static func merge(
        shared: [AcceptedInvitationDestination],
        accepted: [AcceptedInvitationDestination]
    ) -> [AcceptedInvitationDestination] {
        var merged = accepted
        let acceptedIDs = Set(accepted.map(\.id))
        for destination in shared where !acceptedIDs.contains(destination.id) {
            merged.append(destination)
        }
        return merged
    }

    nonisolated static func destinations(
        fromProjects projects: [SharedProjectItem],
        scans: [SharedScanItem]
    ) -> [AcceptedInvitationDestination] {
        let projectDestinations = projects.compactMap(destination(from:))
        let scanDestinations = scans.compactMap(destination(from:))
        return projectDestinations + scanDestinations
    }

    private func reload() async {
        requestGeneration += 1
        let generation = requestGeneration
        viewState = sharedDestinations.isEmpty ? .loading : viewState

        do {
            async let projects = service.fetchSharedProjects()
            async let scans = service.fetchSharedScans()
            let (fetchedProjects, fetchedScans) = try await (projects, scans)
            guard generation == requestGeneration else { return }

            sharedDestinations = Self.destinations(fromProjects: fetchedProjects, scans: fetchedScans)
            viewState = sharedDestinations.isEmpty ? .empty : .loaded
        } catch {
            guard generation == requestGeneration else { return }
            if sharedDestinations.isEmpty {
                viewState = .failed
            }
        }
    }

    private nonisolated static func destination(
        from project: SharedProjectItem
    ) -> AcceptedInvitationDestination? {
        guard project.status.isActive, let detail = project.detailProject else { return nil }
        return .project(detail)
    }

    private nonisolated static func destination(
        from scan: SharedScanItem
    ) -> AcceptedInvitationDestination? {
        guard scan.status.isActive, let detail = scan.detailScan else { return nil }
        return .scan(
            ViewerInput(
                scanID: detail.id,
                scanName: detail.name,
                modelURL: detail.localModelURL
            )
        )
    }
}
