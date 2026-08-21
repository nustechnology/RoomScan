//
//  RemoteProjectsService+ScanManagement.swift
//  roomscan
//

import Foundation

extension RemoteProjectsService {
    func isScanNameDuplicate(name: String, projectID: String) async throws -> Bool {
        try await localStore.isScanNameDuplicate(name: name, projectID: projectID)
    }

    func renameScan(projectID: String, scanID: String, name: String) async throws -> RoomScanSummary {
        try await localStore.renameScan(projectID: projectID, scanID: scanID, name: name)
    }

    func deleteScan(projectID: String, scanID: String) async throws {
        do {
            let revision = await revisionStore.currentRevision(for: scanID)
            let _: EmptyAPIResponse = try await httpClient.request(
                APIEndpoint(
                    path: "/api/v1/scans/\(scanID)",
                    method: .delete,
                    revision: revision
                )
            )
            await revisionStore.advance(for: scanID)
            // The server is the source of truth. A stale local cache must not
            // turn a successful remote deletion into a UI failure.
            try? await localStore.deleteScan(projectID: projectID, scanID: scanID)
        } catch let error as HTTPClientError {
            throw mapHTTPClientError(error, operation: .deleteScan)
        }
    }

    func mapHTTPClientError(
        _ error: HTTPClientError,
        operation: RemoteProjectsHTTPErrorMapper.Operation
    ) -> ProjectsServiceError {
        RemoteProjectsHTTPErrorMapper.map(error, operation: operation)
    }
}
