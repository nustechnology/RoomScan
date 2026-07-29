//
//  NotesService.swift
//  roomscan
//

import Foundation
import simd

protocol NotesService: AnyObject {
    func fetchNotes(scanID: String) async throws -> [SpatialNote]
    func createNote(
        scanID: String,
        title: String,
        description: String,
        color: NoteColor,
        position: SIMD3<Float>
    ) async throws -> SpatialNote
    func updateNote(
        scanID: String,
        noteID: String,
        title: String,
        description: String,
        color: NoteColor
    ) async throws -> SpatialNote
    func moveNote(
        scanID: String,
        noteID: String,
        position: SIMD3<Float>
    ) async throws -> SpatialNote
    func deleteNote(scanID: String, noteID: String) async throws
}
