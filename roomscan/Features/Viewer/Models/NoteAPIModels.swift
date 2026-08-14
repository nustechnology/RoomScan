//
//  NoteAPIModels.swift
//  roomscan
//

import Foundation
import simd

struct NotePositionDTO: Codable, Sendable, Equatable {
    let x: Float
    let y: Float
    let z: Float

    init(_ vector: SIMD3<Float>) {
        x = vector.x
        y = vector.y
        z = vector.z
    }

    var simdValue: SIMD3<Float> {
        SIMD3(x, y, z)
    }
}

struct NoteCreatorDTO: Decodable, Sendable, Equatable {
    let id: String
    let email: String?
}

struct NotePermissionsDTO: Decodable, Sendable, Equatable {
    let role: String
    let canView: Bool
    let canEdit: Bool
    let canDelete: Bool
}

struct NoteDTO: Decodable, Sendable, Equatable {
    let id: String
    let scanId: String
    let content: String
    let color: String
    let position: NotePositionDTO
    let orientation: NotePositionDTO
    let modelVersion: String
    let creator: NoteCreatorDTO
    let createdAt: Date
    let updatedAt: Date
    let permissions: NotePermissionsDTO
}

struct NotesListAPIResponse: Decodable, Sendable {
    let items: [NoteDTO]
    let pagination: NotesPaginationDTO
}

struct NotesPaginationDTO: Decodable, Sendable, Equatable {
    let page: Int
    let limit: Int
    let total: Int
    let totalPages: Int
}

enum NotesAPISort: String, Sendable {
    case createdAtDesc = "createdAt:desc"
    case createdAtAsc = "createdAt:asc"
    case updatedAtDesc = "updatedAt:desc"
    case updatedAtAsc = "updatedAt:asc"
}

struct CreateNoteAPIRequest: Encodable, Sendable {
    let content: String
    let color: String
    let position: NotePositionDTO
    let orientation: NotePositionDTO
    let modelVersion: String
}

struct UpdateNoteAPIRequest: Encodable, Sendable {
    let content: String
    let color: String
}

struct MoveNoteAPIRequest: Encodable, Sendable {
    let position: NotePositionDTO
    let orientation: NotePositionDTO
    let modelVersion: String
}

enum NoteAPIIntegration {
    static let defaultPageSize = 20
    static let defaultSort = NotesAPISort.updatedAtDesc
}

enum NoteAPIMapping {
    static func toSpatialNote(_ dto: NoteDTO) -> SpatialNote {
        let color = NoteColor(apiValue: dto.color) ?? .default
        #if DEBUG
        if NoteColor(apiValue: dto.color) == nil {
            print("[Notes] unknown color=\(dto.color); using default")
        }
        #endif
        let parsedContent = splitContent(dto.content)

        return SpatialNote(
            id: dto.id,
            title: parsedContent.title,
            detail: parsedContent.detail,
            color: color,
            position: dto.position.simdValue,
            orientation: dto.orientation.simdValue,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            modelVersion: dto.modelVersion
        )
    }

    static func makeContent(title: String, description: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (trimmedTitle.isEmpty, trimmedDescription.isEmpty) {
        case (true, true):
            return ""
        case (false, true):
            return String(trimmedTitle.prefix(NoteContentLimits.title))
        case (true, false):
            return String(trimmedDescription.prefix(NoteContentLimits.description))
        case (false, false):
            let boundedTitle = String(trimmedTitle.prefix(NoteContentLimits.title))
            let boundedDescription = String(trimmedDescription.prefix(NoteContentLimits.description))
            return "\(boundedTitle)\n\(boundedDescription)"
        }
    }

    static func splitContent(_ content: String) -> (title: String, detail: String) {
        if let newlineIndex = content.firstIndex(of: "\n") {
            let title = String(content[..<newlineIndex])
            let detail = String(content[content.index(after: newlineIndex)...])
            return (title, detail)
        }

        let title = String(content.prefix(NoteContentLimits.title))
        let detail = String(content.dropFirst(NoteContentLimits.title))
        return (title, detail)
    }
}

extension NoteColor {
    var apiValue: String {
        rawValue.uppercased()
    }

    init?(apiValue: String) {
        self.init(rawValue: apiValue.lowercased())
    }
}
