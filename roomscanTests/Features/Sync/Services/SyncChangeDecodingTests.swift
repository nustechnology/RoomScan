//
//  SyncChangeDecodingTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

@MainActor
struct SyncChangeDecodingTests {
    @Test func fetchChangesDecodesDeleteWithNullData() throws {
        let json = Data(
            """
            {
              "changes": [
                {
                  "resourceId": "project-deleted",
                  "operation": "DELETE",
                  "revision": 3,
                  "syncStatus": "SYNCED",
                  "changedAt": "2026-08-24T02:01:21.114Z",
                  "cursor": "c-del",
                  "deletedAt": "2026-08-24T02:01:21.114Z",
                  "resourceType": "PROJECT",
                  "data": null
                }
              ],
              "nextCursor": "next"
            }
            """.utf8
        )
        let response = try LiveHTTPClient.makeAPIDecoder().decode(SyncChangesAPIResponse.self, from: json)
        let change = try #require(response.changes.first?.toDomain())
        #expect(change.operation == .delete)
        #expect(change.payload == nil)
        #expect(change.resourceType == .project)
    }
    @Test func fetchChangesDecodesUpsertWhenDataKeyIsMissing() throws {
        let json = Data(
            """
            {
              "changes": [
                {
                  "resourceId": "project-1",
                  "operation": "UPSERT",
                  "revision": 1,
                  "resourceType": "PROJECT"
                }
              ],
              "nextCursor": null
            }
            """.utf8
        )
        let response = try LiveHTTPClient.makeAPIDecoder().decode(SyncChangesAPIResponse.self, from: json)
        let change = try #require(response.changes.first?.toDomain())
        #expect(change.operation == .upsert)
        #expect(change.payload == nil)
        #expect(change.resourceType == .project)
    }
    @Test func unknownOperationIsSkippedByToDomainMapping() throws {
        let json = Data(
            """
            {
              "changes": [
                {
                  "resourceId": "project-1",
                  "operation": "MERGE",
                  "revision": 1,
                  "resourceType": "PROJECT",
                  "data": null
                }
              ],
              "nextCursor": "next"
            }
            """.utf8
        )
        let response = try LiveHTTPClient.makeAPIDecoder().decode(SyncChangesAPIResponse.self, from: json)
        let item = try #require(response.changes.first)
        #expect(item.toDomain() == nil)
    }
    @Test func unknownResourceTypeIsSkippedByToDomainMapping() throws {
        let json = Data(
            """
            {
              "changes": [
                {
                  "resourceId": "project-1",
                  "operation": "UPSERT",
                  "revision": 1,
                  "resourceType": "ARCHIVE",
                  "data": null
                }
              ],
              "nextCursor": "next"
            }
            """.utf8
        )
        let response = try LiveHTTPClient.makeAPIDecoder().decode(SyncChangesAPIResponse.self, from: json)
        let item = try #require(response.changes.first)
        #expect(item.toDomain() == nil)
    }

    @Test func fetchChangesKeepsRevisionNilWhenAbsent() throws {
        let json = Data(
            """
            {
              "changes": [
                {
                  "resourceId": "project-1",
                  "operation": "UPSERT",
                  "resourceType": "PROJECT",
                  "changedAt": "2026-08-24T02:01:21.114Z",
                  "cursor": "c-1",
                  "data": {
                    "id": "project-1",
                    "ownerId": "user-1",
                    "ownerEmail": "owner@example.com",
                    "name": "Renamed",
                    "description": null,
                    "createdAt": "2026-01-01T00:00:00.000Z",
                    "updatedAt": "2026-08-24T02:01:21.114Z",
                    "lastSyncedAt": null
                  }
                }
              ],
              "nextCursor": null
            }
            """.utf8
        )
        let response = try LiveHTTPClient.makeAPIDecoder().decode(SyncChangesAPIResponse.self, from: json)
        let change = try #require(response.changes.first?.toDomain())
        #expect(change.revision == nil)
        #expect(change.resourceId == "project-1")
        #expect(change.operation == .upsert)
    }

    @Test func fetchChangesKeepsRevisionNilWhenNull() throws {
        let json = Data(
            """
            {
              "changes": [
                {
                  "resourceId": "project-1",
                  "operation": "DELETE",
                  "revision": null,
                  "resourceType": "PROJECT",
                  "deletedAt": "2026-08-24T02:01:21.114Z",
                  "data": null
                }
              ],
              "nextCursor": null
            }
            """.utf8
        )
        let response = try LiveHTTPClient.makeAPIDecoder().decode(SyncChangesAPIResponse.self, from: json)
        let change = try #require(response.changes.first?.toDomain())
        #expect(change.revision == nil)
        #expect(change.operation == .delete)
    }

    @Test func fetchChangesSkipsMalformedItemAndKeepsKnownChanges() throws {
        let json = Data(
            """
            {
              "changes": [
                {
                  "resourceId": "project-poison",
                  "operation": "UPSERT",
                  "revision": 1,
                  "resourceType": "PROJECT",
                  "data": {
                    "id": "project-poison",
                    "ownerId": "user-1",
                    "ownerEmail": "user@example.com",
                    "name": "Poison",
                    "createdAt": "not-a-date",
                    "updatedAt": "2026-08-24T02:01:21.114Z"
                  }
                },
                {
                  "resourceId": "project-2",
                  "operation": "UPSERT",
                  "revision": 2,
                  "syncStatus": "SYNCED",
                  "changedAt": "2026-08-24T02:01:21.114Z",
                  "cursor": "c2",
                  "resourceType": "PROJECT",
                  "data": {
                    "id": "project-2",
                    "ownerId": "user-1",
                    "ownerEmail": "user@example.com",
                    "name": "Known",
                    "description": null,
                    "createdAt": "2026-08-24T02:01:21.114Z",
                    "updatedAt": "2026-08-24T02:01:21.114Z",
                    "lastSyncedAt": null
                  }
                }
              ],
              "nextCursor": "next"
            }
            """.utf8
        )
        let response = try LiveHTTPClient.makeAPIDecoder().decode(SyncChangesAPIResponse.self, from: json)
        #expect(response.skippedChangeCount == 1)
        #expect(response.changes.count == 1)
        let change = try #require(response.changes.first?.toDomain())
        #expect(change.resourceId == "project-2")
        #expect(change.operation == .upsert)
    }

    @Test func projectPayloadAllowsNullUpdatedAt() throws {
        let json = Data(
            """
            {
              "changes": [
                {
                  "resourceId": "project-1",
                  "operation": "UPSERT",
                  "revision": 2,
                  "resourceType": "PROJECT",
                  "data": {
                    "id": "project-1",
                    "ownerId": "user-1",
                    "ownerEmail": "user@example.com",
                    "name": "Renamed",
                    "description": null,
                    "createdAt": "2026-08-24T02:01:21.114Z",
                    "updatedAt": null,
                    "lastSyncedAt": null
                  }
                }
              ],
              "nextCursor": null
            }
            """.utf8
        )
        let response = try LiveHTTPClient.makeAPIDecoder().decode(SyncChangesAPIResponse.self, from: json)
        #expect(response.skippedChangeCount == 0)
        let change = try #require(response.changes.first?.toDomain())
        guard case let .project(payload)? = change.payload else {
            Issue.record("Expected project payload")
            return
        }
        #expect(payload.name == "Renamed")
        #expect(payload.updatedAt == nil)
    }
}
