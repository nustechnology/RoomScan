//
//  NoteAPIModelsTests.swift
//  roomscanTests
//

import Foundation
import simd
import Testing
@testable import roomscan

struct NoteAPIModelsTests {
    @Test func splitContentSeparatesSingleLineContentWithoutDuplicatingIt() {
        let content = String(repeating: "a", count: NoteContentLimits.title + 10)

        let result = NoteAPIMapping.splitContent(content)

        #expect(result.title == String(repeating: "a", count: NoteContentLimits.title))
        #expect(result.detail == String(repeating: "a", count: 10))
    }

    @Test func unknownColorUsesDefaultAndKeepsNoteVisible() {
        let note = NoteAPIMapping.toSpatialNote(
            NoteDTO(
                id: "note-1",
                scanId: "scan-1",
                title: "Title",
                content: "Detail",
                color: "MAGENTA",
                position: NotePositionDTO(SIMD3(1, 2, 3)),
                orientation: NotePositionDTO(.zero),
                modelVersion: "1",
                creator: NoteCreatorDTO(id: "user-1", email: nil),
                createdAt: .now,
                updatedAt: .now,
                permissions: NotePermissionsDTO(role: "OWNER", canView: true, canEdit: true, canDelete: true)
            )
        )

        #expect(note.color == .default)
        #expect(note.title == "Title")
        #expect(note.detail == "Detail")
    }

    @Test func currentFormatPreservesMultilineDescription() throws {
        let description = "Left wall, near window\nWidens after rain"
        let dto = try LiveHTTPClient.makeAPIDecoder().decode(
            NoteDTO.self,
            from: Data(currentFormatNoteJSON.utf8)
        )

        #expect(dto.title == "Crack")
        #expect(dto.content == description)

        let note = NoteAPIMapping.toSpatialNote(dto)

        #expect(note.title == "Crack")
        #expect(note.detail == description)
    }

    @Test func legacyFormatIsSplitDuringDecoding() throws {
        let json = """
        {"id":"note-1","scanId":"scan-1","content":"Title\\nDescription","color":"YELLOW","position":{"x":0,"y":0,"z":0},"orientation":{"x":0,"y":0,"z":0},"modelVersion":"1","creator":{"id":"user-1"},"createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z","permissions":{"role":"OWNER","canView":true,"canEdit":true,"canDelete":true}}
        """

        let note = try LiveHTTPClient.makeAPIDecoder().decode(NoteDTO.self, from: Data(json.utf8))

        #expect(note.title == "Title")
        #expect(note.content == "Description")
    }

    @Test func fetchNotesStopsWhenAnEmptyPageClaimsMorePages() async throws {
        let client = SequencedHTTPClient(responses: [notesPage(items: [noteJSON]), notesPage(items: [])])
        let service = RemoteNotesService(httpClient: client)

        let notes = try await service.fetchNotes(scanID: "scan-1")

        #expect(notes.count == 1)
        #expect(client.requestCount == 2)
    }

    private var noteJSON: String {
        """
        {"id":"note-1","scanId":"scan-1","title":"Title","content":"Detail","color":"YELLOW","position":{"x":0,"y":0,"z":0},"orientation":{"x":0,"y":0,"z":0},"modelVersion":"1","creator":{"id":"user-1"},"createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z","permissions":{"role":"OWNER","canView":true,"canEdit":true,"canDelete":true}}
        """
    }

    private var currentFormatNoteJSON: String {
        """
        {"id":"note-1","scanId":"scan-1","title":"Crack","content":"Left wall, near window\\nWidens after rain","color":"YELLOW","position":{"x":0,"y":0,"z":0},"orientation":{"x":0,"y":0,"z":0},"modelVersion":"1","creator":{"id":"user-1"},"createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z","permissions":{"role":"OWNER","canView":true,"canEdit":true,"canDelete":true}}
        """
    }

    private func notesPage(items: [String]) -> Data {
        Data("{\"items\":[\(items.joined(separator: ","))],\"pagination\":{\"page\":1,\"limit\":20,\"total\":40,\"totalPages\":2}}".utf8)
    }
}

private final class SequencedHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [Data]
    private(set) var requestCount = 0

    init(responses: [Data]) {
        self.responses = responses
    }

    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        let data = lock.withLock { () -> Data in
            requestCount += 1
            return responses.removeFirst()
        }
        return try LiveHTTPClient.makeAPIDecoder().decode(T.self, from: data)
    }
}
