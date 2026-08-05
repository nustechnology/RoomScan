//
//  PendingAcceptedSharedIngestQueue.swift
//  roomscan
//

import Foundation

/// Retains accepted invitation destinations until their Shared With Me upsert succeeds.
/// Failed upserts are retried before Shared With Me refreshes, so a transient failure
/// does not permanently drop the item when `fetch` alone cannot recreate it.
@MainActor
final class PendingAcceptedSharedIngestQueue {
    private let service: any SharedService
    private(set) var pendingDestinations: [AcceptedInvitationDestination] = []

    init(service: any SharedService) {
        self.service = service
    }

    /// Attempts to upsert the destination. On failure, retains it for a later retry.
    @discardableResult
    func ingest(_ destination: AcceptedInvitationDestination) async -> Bool {
        do {
            try await upsert(destination)
            removePending(id: destination.id)
            return true
        } catch {
            storePending(destination)
            return false
        }
    }

    /// Retries every retained destination. Successful upserts are removed from the queue.
    func retryPending() async {
        let snapshot = pendingDestinations
        for destination in snapshot {
            _ = await ingest(destination)
        }
    }

    private func storePending(_ destination: AcceptedInvitationDestination) {
        pendingDestinations.removeAll { $0.id == destination.id }
        pendingDestinations.append(destination)
    }

    private func removePending(id: String) {
        pendingDestinations.removeAll { $0.id == id }
    }

    private func upsert(_ destination: AcceptedInvitationDestination) async throws {
        switch destination {
        case .project(let project):
            let item = SharedProjectItem.make(
                from: project,
                status: .active,
                statusChangedAt: Date()
            )
            try await service.ingestSharedProject(item)
        case .scan(let item):
            try await service.ingestSharedScan(item)
        }
    }
}
