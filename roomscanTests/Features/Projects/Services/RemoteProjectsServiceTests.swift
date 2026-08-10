//
//  RemoteProjectsServiceTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

struct RemoteProjectsServiceTests {
    @Test func createProject_postsExpectedJSONAndCachesLocally() async throws {
        let httpClient = FakeHTTPClient { endpoint in
            #expect(endpoint.path == "/api/v1/projects")
            #expect(endpoint.method == .post)
            guard let body = endpoint.body,
                  let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            else {
                Issue.record("Expected JSON body for create project")
                return .failure(.decodingError(underlying: "test", bodyPreview: ""))
            }
            #expect(object["name"] as? String == "New Project")
            #expect(object["description"] as? String == "Desc")
            return .success(RemoteProjectsServiceFixtures.sampleProjectJSON(
                id: "created-1",
                name: "New Project",
                description: "Desc"
            ))
        }
        let localStore = MockProjectsService(projects: [], simulatedDelayNanoseconds: 0)
        let service = RemoteProjectsService(httpClient: httpClient, localStore: localStore)

        let created = try await service.createProject(name: "New Project", projectDescription: "Desc")
        #expect(created.id == "created-1")
        #expect(created.name == "New Project")
        #expect(created.description == "Desc")

        let cached = try await localStore.fetchProjects(page: 1, pageSize: 10)
        #expect(cached.projects.contains { $0.id == "created-1" })
    }

    @Test @MainActor
    func createProject_withLocalCache_persistsAcrossReload() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteProjectsLocalCache_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let httpClient = FakeHTTPClient { _ in
            .success(RemoteProjectsServiceFixtures.sampleProjectJSON(
                id: "persisted-1",
                name: "Persisted",
                description: "Keep"
            ))
        }
        let localStore = LocalProjectsService(directory: tempDir, seedIfEmpty: false)
        let service = RemoteProjectsService(httpClient: httpClient, localStore: localStore)

        _ = try await service.createProject(name: "Persisted", projectDescription: "Keep")

        let reloadedStore = LocalProjectsService(directory: tempDir, seedIfEmpty: false)
        let cached = try await reloadedStore.fetchProject(id: "persisted-1")
        #expect(cached.name == "Persisted")
        #expect(cached.description == "Keep")
    }

    @Test func createProject_sendsNullDescriptionWhenEmpty() async throws {
        let httpClient = FakeHTTPClient { endpoint in
            guard let body = endpoint.body,
                  let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            else {
                Issue.record("Expected JSON body")
                return .failure(.decodingError(underlying: "test", bodyPreview: ""))
            }
            #expect(object["name"] as? String == "Only Name")
            #expect(object["description"] is NSNull)
            return .success(RemoteProjectsServiceFixtures.sampleProjectJSON(
                id: "created-2",
                name: "Only Name",
                description: nil
            ))
        }
        let service = RemoteProjectsService(
            httpClient: httpClient,
            localStore: MockProjectsService(projects: [], simulatedDelayNanoseconds: 0)
        )

        let created = try await service.createProject(name: "Only Name", projectDescription: "   ")
        #expect(created.name == "Only Name")
        #expect(created.description == "")
    }

    @Test func createProject_mapsValidationError() async {
        let httpClient = FakeHTTPClient { _ in
            .failure(
                .serverError(
                    statusCode: 400,
                    apiError: APIErrorResponse(
                        error: APIErrorBody(code: "VALIDATION", message: "Invalid", details: nil),
                        requestId: "req-1"
                    )
                )
            )
        }
        let service = RemoteProjectsService(
            httpClient: httpClient,
            localStore: MockProjectsService(projects: [], simulatedDelayNanoseconds: 0)
        )

        await #expect(throws: ProjectsServiceError.invalidProjectName) {
            _ = try await service.createProject(name: "Valid Name", projectDescription: "")
        }
    }

    @Test func createProject_rejectsBlankNameLocally() async {
        let httpClient = FakeHTTPClient { _ in
            Issue.record("HTTP should not be called for invalid names")
            return .failure(.networkError)
        }
        let service = RemoteProjectsService(
            httpClient: httpClient,
            localStore: MockProjectsService(projects: [], simulatedDelayNanoseconds: 0)
        )

        await #expect(throws: ProjectsServiceError.invalidProjectName) {
            _ = try await service.createProject(name: "   ", projectDescription: "")
        }
    }
}

struct RemoteProjectsServiceFetchTests {
    @Test func fetchProjects_sendsQueryAndMapsPage() async throws {
        let httpClient = FakeHTTPClient { endpoint in
            #expect(endpoint.path == "/api/v1/projects")
            #expect(endpoint.method == .get)
            let query = Dictionary(uniqueKeysWithValues: endpoint.queryItems.map { ($0.name, $0.value ?? "") })
            #expect(query["page"] == "1")
            #expect(query["limit"] == "5")
            #expect(query["sort"] == "updatedAt:desc")
            return .success(RemoteProjectsServiceFixtures.sampleProjectsListJSON())
        }
        let localStore = MockProjectsService(projects: [], simulatedDelayNanoseconds: 0)
        let service = RemoteProjectsService(httpClient: httpClient, localStore: localStore)

        let page = try await service.fetchProjects(page: 1, pageSize: 5)
        #expect(page.projects.count == 1)
        #expect(page.projects.first?.id == "list-1")
        #expect(page.projects.first?.scanCount == 2)
        #expect(page.projects.first?.roomScans.count == 1)
        #expect(page.projects.first?.roomScans.first?.id == "list-scan-1")
        #expect(page.hasMore)

        let cached = try await localStore.fetchProject(id: "list-1")
        #expect(cached.name == "Listed Project")
    }

    @Test func fetchProject_getsDetailByID() async throws {
        let httpClient = FakeHTTPClient { endpoint in
            #expect(endpoint.path == "/api/v1/projects/detail-1")
            #expect(endpoint.method == .get)
            return .success(RemoteProjectsServiceFixtures.sampleProjectJSON(
                id: "detail-1",
                name: "Detail Project",
                description: "Info"
            ))
        }
        let service = RemoteProjectsService(
            httpClient: httpClient,
            localStore: MockProjectsService(projects: [], simulatedDelayNanoseconds: 0)
        )

        let project = try await service.fetchProject(id: "detail-1")
        #expect(project.id == "detail-1")
        #expect(project.name == "Detail Project")
        #expect(project.description == "Info")
    }

    @Test func fetchProject_mapsNestedScansFromAPI() async throws {
        let httpClient = FakeHTTPClient { _ in
            .success(RemoteProjectsServiceFixtures.sampleProjectJSON(
                id: "detail-1",
                name: "Detail Project",
                description: "Info",
                scansJSON: RemoteProjectsServiceFixtures.diningScanJSON,
                scanCount: 1
            ))
        }
        let service = RemoteProjectsService(
            httpClient: httpClient,
            localStore: MockProjectsService(projects: [], simulatedDelayNanoseconds: 0)
        )

        let project = try await service.fetchProject(id: "detail-1")
        #expect(project.roomScans.count == 1)
        #expect(project.roomScans.first?.id == "api-scan-1")
        #expect(project.roomScans.first?.name == "Dining")
        #expect(project.roomScans.first?.noteCount == 4)
        #expect(project.roomScans.first?.syncStatus == .synced)
        #expect(project.scanCount == 1)
    }

    @Test func fetchProject_preservesLocalRoomScans() async throws {
        let existingScan = RoomScanSummary(
            id: "scan-1",
            name: "Kitchen",
            createdAt: Date(timeIntervalSince1970: 1_000),
            thumbnailName: "thumbnail-0",
            syncStatus: .synced,
            notes: []
        )
        let localStore = MockProjectsService(
            projects: [
                ProjectSummary(
                    id: "detail-1",
                    name: "Old Name",
                    roomScans: [existingScan],
                    scanCount: 1
                )
            ],
            simulatedDelayNanoseconds: 0
        )
        let httpClient = FakeHTTPClient { _ in
            .success(RemoteProjectsServiceFixtures.sampleProjectJSON(
                id: "detail-1",
                name: "Detail Project",
                description: "Info"
            ))
        }
        let service = RemoteProjectsService(httpClient: httpClient, localStore: localStore)

        let project = try await service.fetchProject(id: "detail-1")
        #expect(project.name == "Detail Project")
        #expect(project.roomScans.count == 1)
        #expect(project.roomScans.first?.id == "scan-1")

        let cached = try await localStore.fetchProject(id: "detail-1")
        #expect(cached.roomScans.count == 1)
        #expect(cached.roomScans.first?.id == "scan-1")
    }

    @Test func fetchProject_mergesAPIScansOverMatchingLocal() async throws {
        let existingScan = RoomScanSummary(
            id: "scan-1",
            name: "Kitchen Local",
            createdAt: Date(timeIntervalSince1970: 1_000),
            localModelURL: URL(fileURLWithPath: "/tmp/kitchen.usdz"),
            thumbnailName: "thumbnail-0",
            syncStatus: .uploading,
            notes: [
                RoomScanNoteSummary(id: "n1", text: "Keep", createdAt: Date(timeIntervalSince1970: 1_100))
            ]
        )
        let localStore = MockProjectsService(
            projects: [
                ProjectSummary(
                    id: "detail-1",
                    name: "Old Name",
                    roomScans: [existingScan],
                    scanCount: 1
                )
            ],
            simulatedDelayNanoseconds: 0
        )
        let httpClient = FakeHTTPClient { _ in
            .success(RemoteProjectsServiceFixtures.sampleProjectJSON(
                id: "detail-1",
                name: "Detail Project",
                description: "Info",
                scansJSON: RemoteProjectsServiceFixtures.kitchenRemoteScanJSON,
                scanCount: 1
            ))
        }
        let service = RemoteProjectsService(httpClient: httpClient, localStore: localStore)

        let project = try await service.fetchProject(id: "detail-1")
        #expect(project.roomScans.count == 1)
        #expect(project.roomScans.first?.name == "Kitchen Remote")
        #expect(project.roomScans.first?.syncStatus == .uploading)
        #expect(project.roomScans.first?.notes.count == 1)
        #expect(project.roomScans.first?.noteCount == 5)
        #expect(project.roomScans.first?.localModelURL != nil)
    }

    @Test func fetchProject_mapsNotFound() async {
        let httpClient = FakeHTTPClient { _ in
            .failure(.serverError(statusCode: 404, apiError: nil))
        }
        let service = RemoteProjectsService(
            httpClient: httpClient,
            localStore: MockProjectsService(projects: [], simulatedDelayNanoseconds: 0)
        )

        await #expect(throws: ProjectsServiceError.projectNotFound) {
            _ = try await service.fetchProject(id: "missing")
        }
    }
}

struct RemoteProjectsServiceMutationTests {
    @Test func updateProject_patchesExpectedJSONAndPreservesLocalScans() async throws {
        let existingScan = RoomScanSummary(
            id: "scan-1",
            name: "Living Room",
            createdAt: Date(timeIntervalSince1970: 1_000),
            thumbnailName: "thumbnail-0",
            syncStatus: .synced,
            notes: []
        )
        let localStore = MockProjectsService(
            projects: [
                ProjectSummary(
                    id: "proj-1",
                    name: "Old Name",
                    description: "Old",
                    roomScans: [existingScan],
                    scanCount: 1
                )
            ],
            simulatedDelayNanoseconds: 0
        )
        let httpClient = FakeHTTPClient { endpoint in
            #expect(endpoint.path == "/api/v1/projects/proj-1")
            #expect(endpoint.method == .patch)
            guard let body = endpoint.body,
                  let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            else {
                Issue.record("Expected JSON body for update project")
                return .failure(.decodingError(underlying: "test", bodyPreview: ""))
            }
            #expect(object["name"] as? String == "New Name")
            #expect(object["description"] as? String == "New Desc")
            return .success(RemoteProjectsServiceFixtures.sampleProjectJSON(
                id: "proj-1",
                name: "New Name",
                description: "New Desc"
            ))
        }
        let service = RemoteProjectsService(httpClient: httpClient, localStore: localStore)

        let updated = try await service.updateProject(
            id: "proj-1",
            name: "New Name",
            description: "New Desc"
        )
        #expect(updated.name == "New Name")
        #expect(updated.description == "New Desc")
        #expect(updated.roomScans.count == 1)
        #expect(updated.roomScans.first?.id == "scan-1")
        #expect(updated.scanCount == 1)
    }

    @Test func updateProject_mapsNotFound() async {
        let httpClient = FakeHTTPClient { _ in
            .failure(.serverError(statusCode: 404, apiError: nil))
        }
        let service = RemoteProjectsService(
            httpClient: httpClient,
            localStore: MockProjectsService(projects: [], simulatedDelayNanoseconds: 0)
        )

        await #expect(throws: ProjectsServiceError.projectNotFound) {
            _ = try await service.updateProject(id: "missing", name: "Name", description: "")
        }
    }

    @Test func deleteProject_sendsDeleteAndClearsLocalCache() async throws {
        let localStore = MockProjectsService(
            projects: [
                ProjectSummary(id: "proj-1", name: "To Delete")
            ],
            simulatedDelayNanoseconds: 0
        )
        let httpClient = FakeHTTPClient { endpoint in
            #expect(endpoint.path == "/api/v1/projects/proj-1")
            #expect(endpoint.method == .delete)
            return .success(Data())
        }
        let service = RemoteProjectsService(httpClient: httpClient, localStore: localStore)

        try await service.deleteProject(id: "proj-1")
        await #expect(throws: ProjectsServiceError.projectNotFound) {
            _ = try await localStore.fetchProject(id: "proj-1")
        }
    }

    @Test func deleteProject_mapsNotFound() async {
        let httpClient = FakeHTTPClient { _ in
            .failure(.serverError(statusCode: 404, apiError: nil))
        }
        let service = RemoteProjectsService(
            httpClient: httpClient,
            localStore: MockProjectsService(projects: [], simulatedDelayNanoseconds: 0)
        )

        await #expect(throws: ProjectsServiceError.projectNotFound) {
            try await service.deleteProject(id: "missing")
        }
    }
}

private enum RemoteProjectsServiceFixtures {
    nonisolated static let diningScanJSON = """
        [
          {
            "id": "api-scan-1",
            "name": "Dining",
            "description": null,
            "thumbnail": "https://example.com/dining.jpg",
            "noteCount": 4,
            "assetStatus": "NONE",
            "syncStatus": "SYNCED",
            "createdAt": "2026-08-11T02:56:32.757Z"
          }
        ]
        """

    nonisolated static let kitchenRemoteScanJSON = """
        [
          {
            "id": "scan-1",
            "name": "Kitchen Remote",
            "description": null,
            "thumbnail": "https://example.com/kitchen.jpg",
            "noteCount": 5,
            "assetStatus": "READY",
            "syncStatus": "SYNCED",
            "createdAt": "2026-08-11T02:56:32.757Z"
          }
        ]
        """

    nonisolated static func sampleProjectsListJSON() -> Data {
        let json = """
        {
          "items": [
            {
              "id": "list-1",
              "name": "Listed Project",
              "description": "Desc",
              "owner": { "id": "owner-1", "email": "owner@example.com" },
              "scanCount": 2,
              "scans": [
                {
                  "id": "list-scan-1",
                  "name": "Lobby",
                  "description": null,
                  "thumbnail": null,
                  "noteCount": 0,
                  "assetStatus": "NONE",
                  "syncStatus": "PENDING",
                  "createdAt": "2026-08-10T03:53:54.365Z"
                }
              ],
              "sharedCount": 0,
              "thumbnail": null,
              "syncStatus": null,
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
          ],
          "pagination": {
            "page": 1,
            "limit": 5,
            "total": 6,
            "totalPages": 2
          }
        }
        """
        return Data(json.utf8)
    }

    nonisolated static func sampleProjectJSON(
        id: String,
        name: String,
        description: String?,
        scansJSON: String = "[]",
        scanCount: Int = 0
    ) -> Data {
        let descriptionJSON: String
        if let description {
            descriptionJSON = "\"\(description)\""
        } else {
            descriptionJSON = "null"
        }
        let json = """
        {
          "id": "\(id)",
          "name": "\(name)",
          "description": \(descriptionJSON),
          "owner": { "id": "owner-1", "email": "owner@example.com" },
          "scanCount": \(scanCount),
          "scans": \(scansJSON),
          "sharedCount": 0,
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
        """
        return Data(json.utf8)
    }
}

private struct FakeHTTPClient: HTTPClient {
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
            let decodeData = data.isEmpty ? Data("{}".utf8) : data
            return try LiveHTTPClient.makeAPIDecoder().decode(T.self, from: decodeData)
        case .failure(let error):
            throw error
        }
    }
}
