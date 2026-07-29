//
//  MockNotesService.swift
//  roomscan
//

import Foundation
import simd

/// In-memory notes store for development, previews, and tests.
@MainActor
final class MockNotesService: NotesService {
    static let shared = MockNotesService()

    private var notesByScanID: [String: [SpatialNote]] = [:]
    private let modelVersion = "sample-1"

    init() {}

    func fetchNotes(scanID: String) async throws -> [SpatialNote] {
        if notesByScanID[scanID] == nil {
            notesByScanID[scanID] = Self.makeSeedNotes(scanID: scanID, modelVersion: modelVersion)
        }
        return notesByScanID[scanID] ?? []
    }

    func createNote(
        scanID: String,
        title: String,
        description: String,
        color: NoteColor,
        position: SIMD3<Float>
    ) async throws -> SpatialNote {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedDescription.isEmpty else {
            throw NotesServiceError.invalidContent
        }

        var notes = try await fetchNotes(scanID: scanID)
        let now = Date()
        let note = SpatialNote(
            id: UUID().uuidString,
            title: String(trimmedTitle.prefix(NoteContentLimits.title)),
            detail: String(trimmedDescription.prefix(NoteContentLimits.description)),
            color: color,
            position: position,
            createdAt: now,
            updatedAt: now,
            modelVersion: modelVersion
        )
        notes.append(note)
        notesByScanID[scanID] = notes
        return note
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

        var notes = try await fetchNotes(scanID: scanID)
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else {
            throw NotesServiceError.noteNotFound
        }

        notes[index].title = String(trimmedTitle.prefix(NoteContentLimits.title))
        notes[index].detail = String(trimmedDescription.prefix(NoteContentLimits.description))
        notes[index].color = color
        notes[index].updatedAt = Date()
        notesByScanID[scanID] = notes
        return notes[index]
    }

    func moveNote(
        scanID: String,
        noteID: String,
        position: SIMD3<Float>
    ) async throws -> SpatialNote {
        var notes = try await fetchNotes(scanID: scanID)
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else {
            throw NotesServiceError.noteNotFound
        }

        notes[index].position = position
        notes[index].updatedAt = Date()
        notesByScanID[scanID] = notes
        return notes[index]
    }

    func deleteNote(scanID: String, noteID: String) async throws {
        var notes = try await fetchNotes(scanID: scanID)
        let originalCount = notes.count
        notes.removeAll { $0.id == noteID }
        guard notes.count < originalCount else {
            throw NotesServiceError.noteNotFound
        }
        notesByScanID[scanID] = notes
    }

    func reset() {
        notesByScanID.removeAll()
    }

    private static func makeSeedNotes(scanID: String, modelVersion: String) -> [SpatialNote] {
        let baseDate = Date(timeIntervalSince1970: 1_750_000_000)
        return [
            SpatialNote(
                id: "\(scanID)-seed-1",
                title: "Wall crack",
                detail: "Needs waterproofing before repainting",
                color: .red,
                position: SIMD3(1.2, 1.4, -0.8),
                createdAt: baseDate.addingTimeInterval(-3_600),
                updatedAt: baseDate.addingTimeInterval(-3_600),
                modelVersion: modelVersion
            ),
            SpatialNote(
                id: "\(scanID)-seed-2",
                title: "TV outlet",
                detail: "Confirm power before mounting bracket",
                color: .blue,
                position: SIMD3(-1.0, 0.9, 1.5),
                createdAt: baseDate.addingTimeInterval(-7_200),
                updatedAt: baseDate.addingTimeInterval(-7_200),
                modelVersion: modelVersion
            ),
            SpatialNote(
                id: "\(scanID)-seed-3",
                title: "Sofa clearance",
                detail: "Keep 80cm walkway in front of sofa",
                color: .green,
                position: SIMD3(0.2, 0.35, 0.4),
                createdAt: baseDate.addingTimeInterval(-10_800),
                updatedAt: baseDate.addingTimeInterval(-10_800),
                modelVersion: modelVersion
            )
        ]
    }
}
