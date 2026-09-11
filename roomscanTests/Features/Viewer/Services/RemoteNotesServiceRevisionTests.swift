//
//  RemoteNotesServiceRevisionTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import simd
import Testing

struct RemoteNotesServiceRevisionTests {
    @Test func createNoteAdvancesParentScanRevision() async throws {
        let scanID = "scan-create-\(UUID().uuidString)"
        await APIRevisionStore.shared.update("4", for: scanID)

        let client = SuccessHTTPClient(data: noteJSON(id: "note-1", scanID: scanID, revision: 1))
        let service = RemoteNotesService(httpClient: client)

        _ = try await service.createNote(
            scanID: scanID,
            input: CreateNoteInput(
                title: "Crack",
                description: "Near window",
                color: .yellow,
                position: .zero,
                orientation: .zero,
                modelVersion: "1"
            )
        )

        #expect(await APIRevisionStore.shared.currentRevision(for: scanID) == "5")
        #expect(await APIRevisionStore.shared.currentRevision(for: "note-1") == "1")
    }

    @Test func deleteNoteAdvancesParentScanRevision() async throws {
        let scanID = "scan-delete-\(UUID().uuidString)"
        let noteID = "note-delete-\(UUID().uuidString)"
        await APIRevisionStore.shared.update("7", for: scanID)
        await APIRevisionStore.shared.update("2", for: noteID)

        let client = SuccessHTTPClient(data: Data("{}".utf8))
        let service = RemoteNotesService(httpClient: client)

        try await service.deleteNote(scanID: scanID, noteID: noteID)

        #expect(await APIRevisionStore.shared.currentRevision(for: scanID) == "8")
        #expect(await APIRevisionStore.shared.currentRevision(for: noteID) == "3")
    }

    @Test func createNoteAdvancesParentScanRevisionOnlyOnceAfterLostResponseRetry() async throws {
        let scanID = "scan-retry-\(UUID().uuidString)"
        await APIRevisionStore.shared.update("4", for: scanID)

        // First attempt: server may have committed, but the client only saw a
        // network failure. Retry succeeds with the same idempotency key.
        let client = ScriptedHTTPClient(results: [
            .failure(.networkError),
            .success(noteJSON(id: "note-retry", scanID: scanID, revision: 1))
        ])
        let service = RemoteNotesService(httpClient: client)

        _ = try await service.createNote(
            scanID: scanID,
            input: CreateNoteInput(
                title: "Crack",
                description: "Near window",
                color: .yellow,
                position: .zero,
                orientation: .zero,
                modelVersion: "1"
            )
        )

        #expect(client.requestCount == 2)
        #expect(await APIRevisionStore.shared.currentRevision(for: scanID) == "5")
        #expect(await APIRevisionStore.shared.currentRevision(for: "note-retry") == "1")
    }

    private func noteJSON(id: String, scanID: String, revision: Int) -> Data {
        Data(
            """
            {
              "id":"\(id)",
              "revision":\(revision),
              "scanId":"\(scanID)",
              "title":"Crack",
              "content":"Near window",
              "color":"YELLOW",
              "position":{"x":0,"y":0,"z":0},
              "orientation":{"x":0,"y":0,"z":0},
              "modelVersion":"1",
              "creator":{"id":"user-1"},
              "createdAt":"2026-01-01T00:00:00Z",
              "updatedAt":"2026-01-01T00:00:00Z",
              "permissions":{"role":"OWNER","canView":true,"canEdit":true,"canDelete":true}
            }
            """.utf8
        )
    }
}

private final class SuccessHTTPClient: HTTPClient, @unchecked Sendable {
    private let data: Data

    init(data: Data) {
        self.data = data
    }

    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        try LiveHTTPClient.makeAPIDecoder().decode(T.self, from: data)
    }
}
