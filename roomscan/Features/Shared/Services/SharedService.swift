//
//  SharedService.swift
//  roomscan
//

import Foundation

protocol SharedService: Sendable {
    func fetchSharedProjects() async throws -> [SharedProjectItem]
    func fetchSharedScans() async throws -> [SharedScanItem]
    func removeSharedItem(id: String, scope: SharedItemScope) async throws
}
