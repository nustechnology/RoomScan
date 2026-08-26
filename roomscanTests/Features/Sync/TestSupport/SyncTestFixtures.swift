//
//  SyncTestFixtures.swift
//  roomscanTests
//

import Foundation
@testable import roomscan

@MainActor
enum SyncTestFixtures {
    static func makeLocalStore() -> LocalProjectsService {
        LocalProjectsService(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("SyncTests-\(UUID().uuidString)", isDirectory: true),
            seedIfEmpty: false
        )
    }

    static func makeProjectChange(id: String, name: String) -> SyncChange {
        SyncChange(
            resourceId: id,
            operation: .upsert,
            revision: 1,
            syncStatus: "SYNCED",
            changedAt: Date(),
            cursor: "c-\(id)",
            deletedAt: nil,
            resourceType: .project,
            payload: .project(
                SyncProjectPayload(
                    id: id,
                    ownerId: "user-1",
                    ownerEmail: "owner@example.com",
                    name: name,
                    description: nil,
                    createdAt: Date(timeIntervalSince1970: 100),
                    updatedAt: Date(timeIntervalSince1970: 200),
                    lastSyncedAt: nil
                )
            )
        )
    }

    static func makeNoteChange(id: String, scanId: String) -> SyncChange {
        SyncChange(
            resourceId: id,
            operation: .upsert,
            revision: 1,
            syncStatus: nil,
            changedAt: Date(),
            cursor: "c-\(id)",
            deletedAt: nil,
            resourceType: .note,
            payload: .note(
                SyncNotePayload(
                    id: id,
                    scanId: scanId,
                    createdById: "user-1",
                    creatorEmail: nil,
                    title: "Title",
                    content: "Body",
                    color: nil,
                    createdAt: Date(timeIntervalSince1970: 300),
                    updatedAt: nil
                )
            )
        )
    }

    static func decodeScanPayload(_ json: String) throws -> SyncScanPayload {
        try LiveHTTPClient.makeAPIDecoder().decode(SyncScanPayload.self, from: Data(json.utf8))
    }

    static func makeScanChange(
        id: String,
        projectId: String,
        name: String,
        cursor: String,
        syncStatus: String = "PENDING"
    ) throws -> SyncChange {
        SyncChange(
            resourceId: id,
            operation: .upsert,
            revision: 1,
            syncStatus: syncStatus,
            changedAt: Date(),
            cursor: cursor,
            deletedAt: nil,
            resourceType: .scan,
            payload: .scan(
                try decodeScanPayload(
                    """
                    {
                      "id": "\(id)",
                      "projectId": "\(projectId)",
                      "createdById": "user-1",
                      "creatorEmail": "owner@example.com",
                      "name": "\(name)",
                      "description": null,
                      "thumbnail": "https://example.com/t.jpg",
                      "assetStatus": "NONE",
                      "modelVersion": 1,
                      "createdAt": "2026-01-01T00:00:00.000Z",
                      "updatedAt": "2026-01-02T00:00:00.000Z",
                      "syncStatus": "\(syncStatus)"
                    }
                    """
                )
            )
        )
    }

    static func makeKitchenScanProject() -> ProjectSummary {
        ProjectSummary(
            id: "project-1",
            name: "Home",
            ownerName: "You",
            createdAt: Date(),
            updatedAt: Date(),
            description: "",
            sharedUserCount: 0,
            roomScans: [
                RoomScanSummary(
                    id: "scan-1",
                    name: "Kitchen",
                    createdAt: Date(),
                    localModelURL: URL(fileURLWithPath: "/tmp/mesh.usdz"),
                    thumbnailName: "thumb.jpg",
                    syncStatus: .synced,
                    notes: [],
                    meshPath: "Scans/scan-1/mesh.usdz",
                    thumbnailPath: "Scans/scan-1/thumbnail.jpg"
                )
            ]
        )
    }
}
