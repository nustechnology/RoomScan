//
//  ProjectSummary.swift
//  roomscan
//

import Foundation

struct ProjectPage: Equatable, Sendable {
    let projects: [ProjectSummary]
    let hasMore: Bool
}

struct ProjectSummary: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let ownerName: String
    let createdAt: Date
    let updatedAt: Date
    let description: String
    let sharedUserCount: Int
    let roomScans: [RoomScanSummary]
}

struct RoomScanSummary: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let createdAt: Date
    let localModelURL: URL?
    let thumbnailName: String
    let syncStatus: RoomScanSyncStatus
    let creatorUserID: String
    let creatorDisplayName: String
    let notes: [RoomScanNoteSummary]
}

struct RoomScanNoteSummary: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let text: String
    let createdAt: Date
}

enum RoomScanSyncStatus: String, CaseIterable, Equatable, Sendable {
    case synced
    case uploading
    case failed

    var localizedTitle: String {
        switch self {
        case .synced:
            return String(localized: "projects.scan.status.synced")
        case .uploading:
            return String(localized: "projects.scan.status.uploading")
        case .failed:
            return String(localized: "projects.scan.status.failed")
        }
    }
}
