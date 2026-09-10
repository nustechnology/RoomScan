//
//  NoteDetailRequest.swift
//  roomscan
//

import Foundation

nonisolated final class NoteDetailRequest {
    var noteID: String?
    var task: Task<Void, Never>?
    /// Bumped on every start/cancel so only the newest in-flight response can update state.
    private(set) var generation = 0

    deinit {
        task?.cancel()
    }

    /// Cancels any prior task, marks `noteID` in flight, and returns the generation for this request.
    func start(noteID: String) -> Int {
        task?.cancel()
        self.noteID = noteID
        generation += 1
        return generation
    }

    func cancel() {
        task?.cancel()
        task = nil
        noteID = nil
        generation += 1
    }

    /// Clears in-flight markers only if this generation is still current.
    func finish(generation expected: Int) {
        guard generation == expected else { return }
        task = nil
        noteID = nil
    }
}
