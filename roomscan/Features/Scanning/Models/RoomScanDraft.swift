//
//  RoomScanDraft.swift
//  roomscan
//

import Foundation

struct RoomScanDraft: Identifiable, Equatable, Sendable {
    let id: String
    let createdAt: Date
    let meshFileURL: URL
    let thumbnailFileURL: URL
    var name: String
    var projectID: String?

    init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        meshFileURL: URL,
        thumbnailFileURL: URL,
        name: String = "",
        projectID: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.meshFileURL = meshFileURL
        self.thumbnailFileURL = thumbnailFileURL
        self.name = name
        self.projectID = projectID
    }
}
