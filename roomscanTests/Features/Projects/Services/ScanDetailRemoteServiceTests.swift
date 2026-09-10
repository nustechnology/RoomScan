//
//  ScanDetailRemoteServiceTests.swift
//  roomscanTests
//

import Foundation
import Testing
@testable import roomscan

struct ScanDetailRemoteServiceTests {
    @Test func updateScanDetailRetriesOnceAfterConflict() async throws {
        let scanID = "scan-conflict-\(UUID().uuidString)"
        await APIRevisionStore.shared.update("3", for: scanID)

        let client = ScriptedHTTPClient(results: [
            .failure(.serverError(statusCode: 409, apiError: nil)),
            .success(scanDetailJSON(id: scanID, revision: 4, name: "Kitchen")),
            .success(scanDetailJSON(id: scanID, revision: 5, name: "Dining Room"))
        ])
        let service = ScanDetailRemoteService(httpClient: client)

        let updated = try await service.updateScanDetail(
            id: scanID,
            name: "Dining Room",
            description: nil
        )

        #expect(updated.name == "Dining Room")
        #expect(client.requestCount == 3)
        #expect(await APIRevisionStore.shared.currentRevision(for: scanID) == "5")

        let patchRevisions = client.recordedEndpoints
            .filter { $0.method == .patch }
            .compactMap { $0.headers["If-Match"] }
        #expect(patchRevisions == ["\"3\"", "\"4\""])
    }

    @Test func updateScanDetailRecoversWhenLocalRevisionIsAhead() async throws {
        let scanID = "scan-ahead-\(UUID().uuidString)"
        // Local overshoot (e.g. optimistic advance that the server did not take).
        await APIRevisionStore.shared.replace("6", for: scanID)

        let client = ScriptedHTTPClient(results: [
            .failure(.serverError(statusCode: 409, apiError: nil)),
            .success(scanDetailJSON(id: scanID, revision: 4, name: "Kitchen")),
            .success(scanDetailJSON(id: scanID, revision: 5, name: "Dining Room"))
        ])
        let service = ScanDetailRemoteService(httpClient: client)

        let updated = try await service.updateScanDetail(
            id: scanID,
            name: "Dining Room",
            description: nil
        )

        #expect(updated.name == "Dining Room")
        #expect(client.requestCount == 3)
        #expect(await APIRevisionStore.shared.currentRevision(for: scanID) == "5")

        let patchRevisions = client.recordedEndpoints
            .filter { $0.method == .patch }
            .compactMap { $0.headers["If-Match"] }
        #expect(patchRevisions == ["\"6\"", "\"4\""])
    }

    @Test func updateScanDetailDoesNotRetryNonConflictErrors() async {
        let scanID = "scan-error-\(UUID().uuidString)"
        await APIRevisionStore.shared.update("2", for: scanID)

        let client = ScriptedHTTPClient(results: [
            .failure(.serverError(statusCode: 500, apiError: nil))
        ])
        let service = ScanDetailRemoteService(httpClient: client)

        await #expect(throws: HTTPClientError.self) {
            _ = try await service.updateScanDetail(
                id: scanID,
                name: "Dining Room",
                description: nil
            )
        }
        #expect(client.requestCount == 1)
    }

    @Test func deleteScanDetailRetriesOnceAfterConflict() async throws {
        let scanID = "scan-delete-conflict-\(UUID().uuidString)"
        await APIRevisionStore.shared.replace("6", for: scanID)

        let client = ScriptedHTTPClient(results: [
            .failure(.serverError(statusCode: 409, apiError: nil)),
            .success(scanDetailJSON(id: scanID, revision: 4, name: "Kitchen")),
            .success(Data("{}".utf8))
        ])
        let service = ScanDetailRemoteService(httpClient: client)

        try await service.deleteScanDetail(id: scanID)

        #expect(client.requestCount == 3)
        #expect(await APIRevisionStore.shared.currentRevision(for: scanID) == "5")

        let deleteRevisions = client.recordedEndpoints
            .filter { $0.method == .delete }
            .compactMap { $0.headers["If-Match"] }
        #expect(deleteRevisions == ["\"6\"", "\"4\""])
    }

    private func scanDetailJSON(id: String, revision: Int, name: String) -> Data {
        Data(
            """
            {
              "id":"\(id)",
              "revision":\(revision),
              "projectId":"project-1",
              "name":"\(name)",
              "creator":{"id":"user-1"},
              "noteCount":1,
              "assetStatus":"UPLOADED",
              "syncStatus":"SYNCED",
              "modelVersion":1,
              "createdAt":"2026-01-01T00:00:00.000Z",
              "updatedAt":"2026-01-01T00:00:00.000Z",
              "permissions":{"role":"OWNER","canView":true,"canEdit":true,"canDelete":true}
            }
            """.utf8
        )
    }
}
