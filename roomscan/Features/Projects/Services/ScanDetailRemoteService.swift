//
//  ScanDetailRemoteService.swift
//  roomscan
//

import Foundation

protocol ScanDetailService: Sendable {
    func fetchScanDetail(id: String) async throws -> ScanDetail
    func updateScanDetail(id: String, name: String, description: String?) async throws -> ScanDetail
    func deleteScanDetail(id: String) async throws
    func downloadModel(scanID: String, to destinationURL: URL) async throws
}

extension ScanDetailService {
    func downloadModel(scanID: String, to destinationURL: URL) async throws {
        throw HTTPClientError.networkError
    }
}

struct ScanDetailRemoteService: ScanDetailService {
    private let httpClient: any HTTPClient
    private let urlSession: URLSession
    private let revisionStore = APIRevisionStore.shared

    /// The caller must inject the app-level authenticated client so session
    /// invalidation is consistently propagated to `AppState`.
    init(httpClient: any HTTPClient, urlSession: URLSession = .shared) {
        self.httpClient = httpClient
        self.urlSession = urlSession
    }

    func fetchScanDetail(id: String) async throws -> ScanDetail {
        let response: ScanDetailAPIResponse = try await httpClient.request(
            APIEndpoint(path: "/api/v1/scans/\(id)")
        )
        await revisionStore.update(response.revision.map(String.init), for: id)
        return try response.toScanDetail()
    }

    func updateScanDetail(id: String, name: String, description: String?) async throws -> ScanDetail {
        let requestBody = ScanDetailUpdateRequest(name: name, description: description)
        let body = try JSONEncoder().encode(requestBody)
        let response: ScanDetailAPIResponse = try await httpClient.request(
            APIEndpoint(
                path: "/api/v1/scans/\(id)", method: .patch, body: body,
                revision: await revisionStore.currentRevision(for: id)
            )
        )
        await revisionStore.update(response.revision.map(String.init), for: id)
        return try response.toScanDetail()
    }

    func deleteScanDetail(id: String) async throws {
        let revision = await revisionStore.currentRevision(for: id)
        let _: EmptyResponse = try await httpClient.request(
            APIEndpoint(
                path: "/api/v1/scans/\(id)", method: .delete,
                revision: revision
            )
        )
        await revisionStore.advance(for: id)
    }

    func downloadModel(scanID: String, to destinationURL: URL) async throws {
        let response: ModelDownloadURLResponse = try await httpClient.request(
            APIEndpoint(path: "/api/v1/scans/\(scanID)/assets/MODEL/download-url")
        )
        let (temporaryURL, urlResponse) = try await urlSession.download(from: response.downloadUrl)
        guard let httpResponse = urlResponse as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw HTTPClientError.networkError
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: temporaryURL
            )
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
    }
}

private struct EmptyResponse: Decodable, Sendable {}

private struct ModelDownloadURLResponse: Decodable, Sendable {
    let downloadUrl: URL
}
