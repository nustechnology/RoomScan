//
//  NoteDetailRequest.swift
//  roomscan
//

import Foundation

nonisolated final class NoteDetailRequest {
    var task: Task<Void, Never>?

    deinit {
        task?.cancel()
    }
}
