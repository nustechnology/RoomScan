//
//  RemoteNotesService.swift
//  roomscan
//

import Foundation
import simd

private struct NotesPage {
    let notes: [SpatialNote]
    let itemCount: Int
    let hasMore: Bool
}

/// Network-backed notes service for the 3D viewer.
final class RemoteNotesService: NotesService, @unchecked Sendable {
    private let httpClient: any HTTPClient
    private static let maximumPageCount = 100

    init(httpClient: any HTTPClient) {
        self.httpClient = httpClient
    }

    func fetchNotes(scanID: String) async throws -> [SpatialNote] {
        var allNotes: [SpatialNote] = []
        for page in 1...Self.maximumPageCount {
            try Task.checkCancellation()
            let response = try await fetchNotesPage(
                scanID: scanID,
                page: page,
                limit: NoteAPIIntegration.defaultPageSize,
                sort: NoteAPIIntegration.defaultSort
            )
            allNotes.append(contentsOf: response.notes)

            guard response.itemCount > 0, response.hasMore else {
                return allNotes
            }
        }

        #if DEBUG
        print("[Notes] pagination limit reached scanID=\(scanID) limit=\(Self.maximumPageCount)")
        #endif
        return allNotes
    }

    func fetchNote(noteID: String) async throws -> SpatialNote {
        let endpoint = APIEndpoint(
            path: "/api/v1/notes/\(noteID)",
            method: .get
        )
        return try await requestNote(endpoint: endpoint)
    }

    private func fetchNotesPage(
        scanID: String,
        page: Int,
        limit: Int,
        sort: NotesAPISort
    ) async throws -> NotesPage {
        let endpoint = APIEndpoint(
            path: "/api/v1/scans/\(scanID)/notes",
            method: .get,
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "sort", value: sort.rawValue)
            ]
        )

        do {
            let response: NotesListAPIResponse = try await httpClient.request(endpoint)
            let notes = response.items.map(NoteAPIMapping.toSpatialNote)
            let hasMore = response.pagination.page < response.pagination.totalPages
            return NotesPage(notes: notes, itemCount: response.items.count, hasMore: hasMore)
        } catch let error as HTTPClientError {
            throw mapHTTPClientError(error)
        } catch {
            throw NotesServiceError.noteNotFound
        }
    }

    func createNote(scanID: String, input: CreateNoteInput) async throws -> SpatialNote {
        let trimmedTitle = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = input.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedDescription.isEmpty else {
            throw NotesServiceError.invalidContent
        }

        let content = NoteAPIMapping.makeContent(title: trimmedTitle, description: trimmedDescription)
        guard !content.isEmpty else {
            throw NotesServiceError.invalidContent
        }

        let body = CreateNoteAPIRequest(
            content: content,
            color: input.color.apiValue,
            position: NotePositionDTO(input.position),
            orientation: NotePositionDTO(input.orientation),
            modelVersion: input.modelVersion
        )
        #if DEBUG
        logCreateRequest(scanID: scanID, input: input)
        #endif
        let endpoint = APIEndpoint(
            path: "/api/v1/scans/\(scanID)/notes",
            method: .post,
            body: try JSONEncoder.apiEncoder.encode(body)
        )

        return try await requestNote(endpoint: endpoint)
    }

    func updateNote(
        scanID: String,
        noteID: String,
        title: String,
        description: String,
        color: NoteColor
    ) async throws -> SpatialNote {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedDescription.isEmpty else {
            throw NotesServiceError.invalidContent
        }

        let content = NoteAPIMapping.makeContent(title: trimmedTitle, description: trimmedDescription)
        guard !content.isEmpty else {
            throw NotesServiceError.invalidContent
        }

        let body = UpdateNoteAPIRequest(
            content: content,
            color: color.apiValue
        )
        let endpoint = APIEndpoint(
            path: "/api/v1/notes/\(noteID)",
            method: .patch,
            body: try JSONEncoder.apiEncoder.encode(body)
        )

        return try await requestNote(endpoint: endpoint)
    }

    func moveNote(noteID: String, input: MoveNoteInput) async throws -> SpatialNote {
        let body = MoveNoteAPIRequest(
            position: NotePositionDTO(input.position),
            orientation: NotePositionDTO(input.orientation),
            modelVersion: input.modelVersion
        )
        let endpoint = APIEndpoint(
            path: "/api/v1/notes/\(noteID)/position",
            method: .patch,
            body: try JSONEncoder.apiEncoder.encode(body)
        )

        return try await requestNote(endpoint: endpoint)
    }

    func deleteNote(scanID: String, noteID: String) async throws {
        let endpoint = APIEndpoint(
            path: "/api/v1/notes/\(noteID)",
            method: .delete
        )

        do {
            let _: EmptyAPIResponse = try await httpClient.request(endpoint)
        } catch let error as HTTPClientError {
            throw mapHTTPClientError(error)
        } catch {
            throw NotesServiceError.noteNotFound
        }
    }

    private func requestNote(endpoint: APIEndpoint) async throws -> SpatialNote {
        do {
            let dto: NoteDTO = try await httpClient.request(endpoint)
            return NoteAPIMapping.toSpatialNote(dto)
        } catch let error as HTTPClientError {
            #if DEBUG
            logRequestFailure(error, endpoint: endpoint)
            #endif
            throw mapHTTPClientError(error)
        } catch let error as NotesServiceError {
            throw error
        } catch {
            throw NotesServiceError.noteNotFound
        }
    }

    #if DEBUG
    private func logCreateRequest(scanID: String, input: CreateNoteInput) {
        print(
            "[Notes] create request scanID=\(scanID) color=\(input.color.apiValue) " +
            "modelVersion=\(input.modelVersion) titleLength=\(input.title.count) " +
            "descriptionLength=\(input.description.count) " +
            "position=(\(input.position.x),\(input.position.y),\(input.position.z)) " +
            "orientation=(\(input.orientation.x),\(input.orientation.y),\(input.orientation.z))"
        )
    }

    private func logRequestFailure(_ error: HTTPClientError, endpoint: APIEndpoint) {
        switch error {
        case .serverError(let statusCode, let apiError):
            print(
                "[Notes] request failed method=\(endpoint.method.rawValue) path=\(endpoint.path) " +
                "status=\(statusCode) code=\(apiError?.error.code ?? "unknown") " +
                "requestId=\(apiError?.requestId ?? "unknown")"
            )
        case .decodingError(_, let bodyPreview):
            print(
                "[Notes] response decode failed method=\(endpoint.method.rawValue) path=\(endpoint.path) " +
                "responseBytes=\(bodyPreview.utf8.count)"
            )
        default:
            print("[Notes] request failed method=\(endpoint.method.rawValue) path=\(endpoint.path) error=\(error)")
        }
    }
    #endif

    private func mapHTTPClientError(_ error: HTTPClientError) -> NotesServiceError {
        switch error {
        case .networkError, .invalidURL, .decodingError:
            return .noteNotFound
        case .serverError(let statusCode, _):
            switch statusCode {
            case 400, 409:
                return .invalidContent
            case 404:
                return .noteNotFound
            default:
                return .noteNotFound
            }
        }
    }
}

private extension JSONEncoder {
    static let apiEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
