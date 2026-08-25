//
//  RemoteSyncServiceTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

struct RemoteSyncServiceTests {
    @Test func fetchSyncStatus_mapsProjectSummaries() async throws {
        let client = SyncHTTPClient { endpoint in
            #expect(endpoint.path == "/api/v1/sync/status")
            #expect(endpoint.method == .get)
            #expect(endpoint.queryItems.isEmpty)
            return .success(Self.statusJSON)
        }
        let service = RemoteSyncService(httpClient: client)

        let items = try await service.fetchSyncStatus()

        #expect(items.count == 2)
        #expect(items[0].projectId == "project-1")
        #expect(items[0].syncStatus == .pending)
        #expect(items[0].pendingCount == 1)
        #expect(items[0].syncingCount == 2)
        #expect(items[0].failedCount == 0)
        #expect(items[0].conflictCount == 1)
        #expect(items[0].unresolvedCount == 4)
        #expect(items[0].requiredAssetsUploaded == false)
        #expect(items[1].syncStatus == .synced)
        #expect(items[1].unresolvedCount == 0)
        #expect(items[1].requiredAssetsUploaded == true)
    }

    @Test func fetchSyncStatus_passesProjectIdQuery() async throws {
        let client = SyncHTTPClient { endpoint in
            #expect(endpoint.path == "/api/v1/sync/status")
            #expect(endpoint.queryItems == [URLQueryItem(name: "projectId", value: "project-1")])
            return .success(Self.singleStatusJSON)
        }
        let service = RemoteSyncService(httpClient: client)

        let items = try await service.fetchSyncStatus(projectId: "project-1")

        #expect(items.count == 1)
        #expect(items[0].projectId == "project-1")
    }

    @Test func fetchSyncStatus_mapsUnauthorized() async {
        let client = SyncHTTPClient { _ in
            .failure(.serverError(statusCode: 401, apiError: nil))
        }
        let service = RemoteSyncService(httpClient: client)

        do {
            _ = try await service.fetchSyncStatus()
            Issue.record("Expected unauthorized error")
        } catch let error as SyncServiceError {
            #expect(error == .unauthorized)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func fetchChanges_mapsCursorAndLimitQuery() async throws {
        let client = SyncHTTPClient { endpoint in
            #expect(endpoint.path == "/api/v1/sync/changes")
            #expect(endpoint.method == .get)
            let items = Dictionary(uniqueKeysWithValues: endpoint.queryItems.map { ($0.name, $0.value) })
            #expect(items["cursor"] == "abc")
            #expect(items["limit"] == "50")
            return .success(Self.changesJSON)
        }
        let service = RemoteSyncService(httpClient: client)

        let page = try await service.fetchChanges(cursor: "abc", since: nil, limit: 50)

        #expect(page.changes.count == 1)
        #expect(page.changes[0].resourceType == .project)
        #expect(page.changes[0].operation == .upsert)
        #expect(page.nextCursor == "next-cursor")
    }

    @Test func fetchChanges_skipsUnknownResourceTypeAndKeepsKnownChanges() async throws {
        let client = SyncHTTPClient { _ in
            .success(
                Data(
                    """
                    {
                      "changes": [
                        {
                          "resourceId": "project-1",
                          "operation": "UPSERT",
                          "revision": 1,
                          "resourceType": "ARCHIVE",
                          "data": null
                        },
                        {
                          "resourceId": "project-2",
                          "operation": "UPSERT",
                          "revision": 2,
                          "syncStatus": "SYNCED",
                          "changedAt": "2026-08-24T02:01:21.114Z",
                          "cursor": "c2",
                          "deletedAt": null,
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
            )
        }
        let service = RemoteSyncService(httpClient: client)

        let page = try await service.fetchChanges(cursor: nil, since: nil, limit: 50)

        #expect(page.changes.count == 1)
        #expect(page.changes[0].resourceId == "project-2")
        #expect(page.changes[0].resourceType == .project)
        #expect(page.nextCursor == "next")
    }

    @Test func fetchChanges_skipsMalformedPayloadAndKeepsKnownChanges() async throws {
        let client = SyncHTTPClient { _ in
            .success(
                Data(
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
                            "name": "Poison",
                            "createdAt": "not-a-date",
                            "updatedAt": null
                          }
                        },
                        {
                          "resourceId": "project-2",
                          "operation": "UPSERT",
                          "revision": 2,
                          "syncStatus": "SYNCED",
                          "changedAt": "2026-08-24T02:01:21.114Z",
                          "cursor": "c2",
                          "deletedAt": null,
                          "resourceType": "PROJECT",
                          "data": {
                            "id": "project-2",
                            "ownerId": "user-1",
                            "ownerEmail": "user@example.com",
                            "name": "Known",
                            "description": null,
                            "createdAt": "2026-08-24T02:01:21.114Z",
                            "updatedAt": null,
                            "lastSyncedAt": null
                          }
                        }
                      ],
                      "nextCursor": "next"
                    }
                    """.utf8
                )
            )
        }
        let service = RemoteSyncService(httpClient: client)

        let page = try await service.fetchChanges(cursor: nil, since: nil, limit: 50)

        #expect(page.changes.count == 1)
        #expect(page.changes[0].resourceId == "project-2")
        guard case let .project(payload)? = page.changes[0].payload else {
            Issue.record("Expected project payload")
            return
        }
        #expect(payload.updatedAt == nil)
        #expect(page.nextCursor == "next")
    }

    @Test func fetchChanges_mapsDecodingError() async {
        let client = SyncHTTPClient { _ in
            .failure(.decodingError(underlying: "bad json", bodyPreview: "{}"))
        }
        let service = RemoteSyncService(httpClient: client)

        do {
            _ = try await service.fetchChanges(cursor: nil, since: nil, limit: 50)
            Issue.record("Expected decoding error")
        } catch let error as SyncServiceError {
            #expect(error == .decoding)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private static let statusJSON = Data(
        """
        {
          "items": [
            {
              "projectId": "project-1",
              "syncStatus": "PENDING",
              "pendingCount": 1,
              "syncingCount": 2,
              "failedCount": 0,
              "conflictCount": 1,
              "lastSyncedAt": "2026-08-24T02:01:39.754Z",
              "requiredAssetsUploaded": false
            },
            {
              "projectId": "project-2",
              "syncStatus": "SYNCED",
              "pendingCount": 0,
              "syncingCount": 0,
              "failedCount": 0,
              "conflictCount": 0,
              "lastSyncedAt": "2026-08-24T02:01:39.754Z",
              "requiredAssetsUploaded": true
            }
          ]
        }
        """.utf8
    )

    private static let singleStatusJSON = Data(
        """
        {
          "items": [
            {
              "projectId": "project-1",
              "syncStatus": "SYNCING",
              "pendingCount": 0,
              "syncingCount": 1,
              "failedCount": 0,
              "conflictCount": 0,
              "lastSyncedAt": null,
              "requiredAssetsUploaded": false
            }
          ]
        }
        """.utf8
    )

    private static let changesJSON = Data(
        """
        {
          "changes": [
            {
              "resourceId": "project-1",
              "operation": "UPSERT",
              "revision": 2,
              "syncStatus": "SYNCED",
              "changedAt": "2026-08-24T02:01:21.114Z",
              "cursor": "c1",
              "deletedAt": null,
              "resourceType": "PROJECT",
              "data": {
                "id": "project-1",
                "ownerId": "user-1",
                "ownerEmail": "user@example.com",
                "name": "District 2",
                "description": "desc",
                "createdAt": "2026-08-24T02:01:21.114Z",
                "updatedAt": "2026-08-24T02:01:21.114Z",
                "lastSyncedAt": "2026-08-24T02:01:21.114Z"
              }
            }
          ],
          "nextCursor": "next-cursor"
        }
        """.utf8
    )
}

private struct SyncHTTPClient: HTTPClient {
    enum Outcome: Sendable {
        case success(Data)
        case failure(HTTPClientError)
    }

    private let handler: @Sendable (APIEndpoint) async -> Outcome

    init(handler: @escaping @Sendable (APIEndpoint) async -> Outcome) {
        self.handler = handler
    }

    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        switch await handler(endpoint) {
        case .success(let data):
            return try LiveHTTPClient.makeAPIDecoder().decode(T.self, from: data.isEmpty ? Data("{}".utf8) : data)
        case .failure(let error):
            throw error
        }
    }
}
