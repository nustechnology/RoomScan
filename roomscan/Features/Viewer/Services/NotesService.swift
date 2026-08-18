//
//  NotesService.swift
//  roomscan
//

import Foundation
import simd

protocol NotesService: AnyObject {
    func fetchNotes(scanID: String) async throws -> [SpatialNote]
    func fetchNote(noteID: String) async throws -> SpatialNote
    func createNote(scanID: String, input: CreateNoteInput) async throws -> SpatialNote
    func updateNote(
        scanID: String,
        noteID: String,
        title: String,
        description: String,
        color: NoteColor
    ) async throws -> SpatialNote
    func moveNote(noteID: String, input: MoveNoteInput) async throws -> SpatialNote
    func deleteNote(scanID: String, noteID: String) async throws
}

/// Real user/editor values used to create a note via the notes API.
struct CreateNoteInput: Sendable {
    let title: String
    let description: String
    let color: NoteColor
    let position: SIMD3<Float>
    let orientation: SIMD3<Float>
    let modelVersion: String
}

/// Real values used to move a note via the notes API.
struct MoveNoteInput: Sendable {
    let position: SIMD3<Float>
    let orientation: SIMD3<Float>
    let modelVersion: String
}
