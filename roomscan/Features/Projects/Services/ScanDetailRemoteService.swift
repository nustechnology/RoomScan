//
//  ScanDetailRemoteService.swift
//  roomscan
//

import Foundation

nonisolated protocol ScanDetailService: Sendable {
    func fetchScanDetail(id: String) async throws -> ScanDetail
    func updateScanDetail(id: String, name: String, description: String?) async throws -> ScanDetail
    func deleteScanDetail(id: String) async throws
    func downloadModel(scanID: String, to destinationURL: URL) async throws
}

extension ScanDetailService {
    nonisolated func downloadModel(scanID: String, to destinationURL: URL) async throws {
        throw HTTPClientError.networkError
    }
}

nonisolated struct ScanDetailRemoteService: ScanDetailService {
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
        // GET is authoritative — replace so a locally overshot revision can recover.
        await revisionStore.replace(response.revision.map(String.init), for: id)
        return try response.toScanDetail()
    }

    func updateScanDetail(id: String, name: String, description: String?) async throws -> ScanDetail {
        let requestBody = ScanDetailUpdateRequest(name: name, description: description)
        let body = try JSONEncoder().encode(requestBody)
        do {
            return try await performUpdateScanDetail(id: id, body: body)
        } catch let error as HTTPClientError where Self.isConflict(error) {
            // Note create/delete can bump the scan revision without the client
            // observing it. Refresh then retry once with a fresh If-Match.
            _ = try await fetchScanDetail(id: id)
            return try await performUpdateScanDetail(id: id, body: body)
        }
    }

    private func performUpdateScanDetail(id: String, body: Data) async throws -> ScanDetail {
        let response: ScanDetailAPIResponse = try await httpClient.request(
            APIEndpoint(
                path: "/api/v1/scans/\(id)",
                method: .patch,
                body: body,
                revision: await revisionStore.currentRevision(for: id)
            )
        )
        await revisionStore.replace(response.revision.map(String.init), for: id)
        return try response.toScanDetail()
    }

    private static func isConflict(_ error: HTTPClientError) -> Bool {
        if case .serverError(let statusCode, _) = error {
            return statusCode == 409
        }
        return false
    }

    func deleteScanDetail(id: String) async throws {
        do {
            try await performDeleteScanDetail(id: id)
        } catch let error as HTTPClientError where Self.isConflict(error) {
            _ = try await fetchScanDetail(id: id)
            try await performDeleteScanDetail(id: id)
        }
    }

    private func performDeleteScanDetail(id: String) async throws {
        let revision = await revisionStore.currentRevision(for: id)
        let _: EmptyAPIResponse = try await httpClient.request(
            APIEndpoint(
                path: "/api/v1/scans/\(id)",
                method: .delete,
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
            _ = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: temporaryURL
            )
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
    }
}

private nonisolated struct ModelDownloadURLResponse: Decodable, Sendable {
    let downloadUrl: URL
}
