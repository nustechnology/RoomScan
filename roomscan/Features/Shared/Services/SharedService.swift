//
//  SharedService.swift
//  roomscan
//

import Foundation

nonisolated protocol SharedService: Sendable {
    func fetchSharedProjects() async throws -> [SharedProjectItem]
    func fetchSharedScans() async throws -> [SharedScanItem]
    func removeSharedItem(id: String, scope: SharedItemScope) async throws
    /// Upserts an accepted invitation project into the Shared With Me source of truth.
    func ingestSharedProject(_ project: SharedProjectItem) async throws
    /// Upserts an accepted invitation scan into the Shared With Me source of truth.
    func ingestSharedScan(_ scan: SharedScanItem) async throws
}
