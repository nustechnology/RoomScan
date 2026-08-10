//
//  ProjectAPIModelsTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

struct ProjectAPIModelsTests {
    @Test func encodeCreateProjectRequest_mapsDescriptionKeyAndNull() throws {
        let emptyDescription = CreateProjectAPIRequest(name: "Villa", projectDescription: nil)
        let emptyData = try JSONEncoder().encode(emptyDescription)
        let emptyObject = try JSONSerialization.jsonObject(with: emptyData) as? [String: Any]
        #expect(emptyObject?["name"] as? String == "Villa")
        #expect(emptyObject?["description"] is NSNull)
        #expect(emptyObject?["projectDescription"] == nil)

        let withDescription = CreateProjectAPIRequest(name: "Villa", projectDescription: "Ocean view")
        let data = try JSONEncoder().encode(withDescription)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["name"] as? String == "Villa")
        #expect(object?["description"] as? String == "Ocean view")
    }

    @Test func encodeUpdateProjectRequest_mapsDescriptionKey() throws {
        let request = UpdateProjectAPIRequest(name: "Renamed", projectDescription: "Updated desc")
        let data = try JSONEncoder().encode(request)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["name"] as? String == "Renamed")
        #expect(object?["description"] as? String == "Updated desc")
        #expect(object?["projectDescription"] == nil)
    }

    @Test func decodeProjectAPIResponse_withFractionalSeconds() throws {
        let json = """
        {
          "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
          "name": "Lakeside Remodel",
          "description": null,
          "owner": { "id": "owner-1", "email": "owner@example.com" },
          "scanCount": 0,
          "scans": [],
          "sharedCount": 2,
          "thumbnail": null,
          "syncStatus": "PENDING",
          "createdAt": "2026-08-10T03:53:54.365Z",
          "updatedAt": "2026-08-10T03:53:54.365Z",
          "permissions": {
            "role": "OWNER",
            "canView": true,
            "canEdit": true,
            "canDelete": true,
            "canShare": true,
            "canCreateScan": true
          }
        }
        """.data(using: .utf8)!

        let response = try LiveHTTPClient.makeAPIDecoder().decode(ProjectAPIResponse.self, from: json)
        let summary = ProjectAPIMapping.toProjectSummary(response)
        #expect(summary.id == response.id)
        #expect(summary.name == "Lakeside Remodel")
        #expect(summary.description == "")
        #expect(summary.ownerName == "owner@example.com")
        #expect(summary.sharedUserCount == 2)
        #expect(summary.roomScans.isEmpty)
        #expect(response.syncStatus == "PENDING")
        #expect(response.scans == [])
    }

    @Test func decodeProjectAPIResponse_withNestedScans() throws {
        let json = """
        {
          "id": "project-1",
          "name": "With Scans",
          "description": "Desc",
          "owner": { "id": "owner-1", "email": "owner@example.com" },
          "scanCount": 1,
          "scans": [
            {
              "id": "scan-1",
              "name": "Kitchen",
              "description": "Main kitchen",
              "thumbnail": "https://example.com/thumb.jpg",
              "noteCount": 3,
              "assetStatus": "NONE",
              "syncStatus": "PENDING",
              "createdAt": "2026-08-11T02:56:32.757Z"
            }
          ],
          "sharedCount": 0,
          "thumbnail": "https://example.com/project.jpg",
          "syncStatus": "PENDING",
          "createdAt": "2026-08-11T02:56:32.757Z",
          "updatedAt": "2026-08-11T02:56:32.757Z",
          "permissions": {
            "role": "OWNER",
            "canView": true,
            "canEdit": true,
            "canDelete": true,
            "canShare": true,
            "canCreateScan": true
          }
        }
        """.data(using: .utf8)!

        let response = try LiveHTTPClient.makeAPIDecoder().decode(ProjectAPIResponse.self, from: json)
        let summary = ProjectAPIMapping.toProjectSummary(response)
        #expect(response.scans?.count == 1)
        #expect(response.scans?.first?.assetStatus == "NONE")
        #expect(summary.roomScans.count == 1)
        #expect(summary.roomScans.first?.id == "scan-1")
        #expect(summary.roomScans.first?.name == "Kitchen")
        #expect(summary.roomScans.first?.noteCount == 3)
        #expect(summary.roomScans.first?.thumbnailPath == "https://example.com/thumb.jpg")
        #expect(summary.roomScans.first?.syncStatus == .pending)
        #expect(summary.scanCount == 1)
        #expect(summary.scansContentState == .local)
    }

    @Test func mergeRoomScans_prefersLocalMeshAndKeepsLocalOnly() {
        let apiScan = RoomScanSummary(
            id: "scan-1",
            name: "Remote Name",
            createdAt: Date(timeIntervalSince1970: 2_000),
            thumbnailName: "",
            syncStatus: .synced,
            notes: [],
            thumbnailPath: "https://example.com/thumb.jpg",
            noteCount: 2
        )
        let localScan = RoomScanSummary(
            id: "scan-1",
            name: "Local Name",
            createdAt: Date(timeIntervalSince1970: 1_000),
            localModelURL: URL(fileURLWithPath: "/tmp/mesh.usdz"),
            thumbnailName: "thumbnail-0",
            syncStatus: .uploading,
            notes: [
                RoomScanNoteSummary(id: "n1", text: "Note", createdAt: Date(timeIntervalSince1970: 1_100))
            ],
            meshPath: "Scans/scan-1/mesh.usdz",
            thumbnailPath: "Scans/scan-1/thumbnail.jpg",
            noteCount: 1
        )
        let localOnly = RoomScanSummary(
            id: "scan-local",
            name: "Pending Upload",
            createdAt: Date(timeIntervalSince1970: 3_000),
            thumbnailName: "thumbnail-1",
            syncStatus: .pending,
            notes: []
        )

        let merged = ProjectAPIMapping.mergeRoomScans(
            apiScans: [apiScan],
            localScans: [localScan, localOnly]
        )
        #expect(merged.count == 2)
        #expect(merged[0].id == "scan-1")
        #expect(merged[0].name == "Remote Name")
        #expect(merged[0].localModelURL == localScan.localModelURL)
        #expect(merged[0].syncStatus == .uploading)
        #expect(merged[0].notes.count == 1)
        #expect(merged[0].noteCount == 2)
        #expect(merged[0].thumbnailPath == "Scans/scan-1/thumbnail.jpg")
        #expect(merged[1].id == "scan-local")
    }

    @Test func decodeProjectAPIResponse_withNullSyncStatus() throws {
        let json = """
        {
          "id": "3250faea-6471-422d-ac1e-3f04bde194d7",
          "name": "Project1",
          "description": "Tetra",
          "owner": { "id": "0b6e11ec-29a6-4a6b-813b-661dedfbeadc", "email": "tony.dev@nustechnology.com" },
          "scanCount": 0,
          "sharedCount": 0,
          "thumbnail": null,
          "syncStatus": null,
          "createdAt": "2026-08-10T07:18:40.458Z",
          "updatedAt": "2026-08-10T07:18:40.458Z",
          "permissions": {
            "role": "OWNER",
            "canView": true,
            "canEdit": true,
            "canDelete": true,
            "canShare": true,
            "canCreateScan": true
          }
        }
        """.data(using: .utf8)!

        let response = try LiveHTTPClient.makeAPIDecoder().decode(ProjectAPIResponse.self, from: json)
        let summary = ProjectAPIMapping.toProjectSummary(response)
        #expect(response.syncStatus == nil)
        #expect(response.scans == nil)
        #expect(summary.id == "3250faea-6471-422d-ac1e-3f04bde194d7")
        #expect(summary.name == "Project1")
        #expect(summary.description == "Tetra")
        #expect(summary.ownerName == "tony.dev@nustechnology.com")
        #expect(summary.sharedUserCount == 0)
        #expect(summary.roomScans.isEmpty)
        #expect(summary.scanCount == 0)
    }

    @Test func decodeProjectsListAPIResponse_itemsAndPagination() throws {
        let json = """
        {
          "items": [
            {
              "id": "3250faea-6471-422d-ac1e-3f04bde194d7",
              "name": "Project1",
              "description": "Tetra",
              "owner": { "id": "owner-1", "email": "owner@example.com" },
              "scanCount": 3,
              "scans": [
                {
                  "id": "scan-a",
                  "name": "Room A",
                  "description": null,
                  "thumbnail": null,
                  "noteCount": 0,
                  "assetStatus": "NONE",
                  "syncStatus": "SYNCED",
                  "createdAt": "2026-08-10T07:18:40.458Z"
                }
              ],
              "sharedCount": 1,
              "thumbnail": null,
              "syncStatus": null,
              "createdAt": "2026-08-10T07:18:40.458Z",
              "updatedAt": "2026-08-10T07:18:40.458Z",
              "permissions": {
                "role": "OWNER",
                "canView": true,
                "canEdit": true,
                "canDelete": true,
                "canShare": true,
                "canCreateScan": true
              }
            }
          ],
          "pagination": {
            "page": 1,
            "limit": 5,
            "total": 6,
            "totalPages": 2
          }
        }
        """.data(using: .utf8)!

        let response = try LiveHTTPClient.makeAPIDecoder().decode(ProjectsListAPIResponse.self, from: json)
        let page = ProjectAPIMapping.toProjectPage(response)
        #expect(response.items.count == 1)
        #expect(response.pagination.totalPages == 2)
        #expect(page.hasMore)
        #expect(page.projects.first?.name == "Project1")
        #expect(page.projects.first?.scanCount == 3)
        #expect(page.projects.first?.roomScans.count == 1)
        #expect(page.projects.first?.roomScans.first?.syncStatus == .synced)
    }
}
