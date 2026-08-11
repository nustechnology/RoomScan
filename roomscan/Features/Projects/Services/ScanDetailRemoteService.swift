//
//  ScanDetailRemoteService.swift
//  roomscan
//

import Foundation

protocol ScanDetailService: Sendable {
    func fetchScanDetail(id: String) async throws -> ScanDetail
    func updateScanDetail(id: String, name: String, description: String?) async throws -> ScanDetail
    func deleteScanDetail(id: String) async throws
}

struct ScanDetailRemoteService: ScanDetailService {
    private let httpClient: any HTTPClient

    /// Backend route contract: `docs/scan-detail-api-contract.md`.
    /// The caller must inject the app-level authenticated client so session
    /// invalidation is consistently propagated to `AppState`.
    init(httpClient: any HTTPClient) {
        self.httpClient = httpClient
    }

    func fetchScanDetail(id: String) async throws -> ScanDetail {
        let response: ScanDetailAPIResponse = try await httpClient.request(
            APIEndpoint(path: "/api/v1/scans/\(id)")
        )
        return try response.toScanDetail()
    }

    func updateScanDetail(id: String, name: String, description: String?) async throws -> ScanDetail {
        let requestBody = ScanDetailUpdateRequest(name: name, description: description)
        let body = try JSONEncoder().encode(requestBody)
        let response: ScanDetailAPIResponse = try await httpClient.request(
            APIEndpoint(path: "/api/v1/scans/\(id)", method: .patch, body: body)
        )
        return try response.toScanDetail()
    }

    func deleteScanDetail(id: String) async throws {
        let _: EmptyResponse = try await httpClient.request(
            APIEndpoint(path: "/api/v1/scans/\(id)", method: .delete)
        )
    }
}

private struct EmptyResponse: Decodable, Sendable {}
