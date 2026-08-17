//
//  RemoteProjectsServiceTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

struct RemoteProjectsServiceSaveScanTests {
    @Test func saveScan_uploadsAndCompletesAssetsBeforePersistingLocally() async throws {
        let project = ProjectSummary(id: "project-1", name: "Project")
        let localStore = MockProjectsService(projects: [project], simulatedDelayNanoseconds: 0)
        let recorder = SaveScanHTTPRecorder()
        let httpClient = FakeHTTPClient { endpoint in
            await recorder.record(endpoint)
            switch endpoint.path {
            case "/api/v1/projects/project-1/scans":
                return .success(RemoteProjectsServiceFixtures.createScanJSON())
            case "/api/v1/upload-sessions/thumbnail-session/complete",
                 "/api/v1/upload-sessions/model-session/complete":
                return .success(Data("{}".utf8))
            case "/api/v1/projects/project-1":
                return .success(RemoteProjectsServiceFixtures.sampleProjectJSON(
                    id: "project-1",
                    name: "Project",
                    description: nil,
                    scanCount: 1
                ))
            default:
                Issue.record("Unexpected HTTP endpoint: \(endpoint.path)")
                return .failure(.networkError)
            }
        }
        let uploadSession = FakeAssetUploadSession { _ in .success(Data()) }
        let service = RemoteProjectsService(
            httpClient: httpClient,
            localStore: localStore,
            uploadSession: uploadSession
        )
        let files = try makeScanFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }

        let saved = try await service.saveScan(
            draft: files.draft,
            name: "Remote Scan",
            projectID: project.id,
            meshURL: files.meshURL
        )

        #expect(saved.id == "remote-scan-id")
        let requests = await recorder.requests
        #expect(requests.first?.path == "/api/v1/projects/project-1/scans")
        #expect(requests.last?.path == "/api/v1/projects/project-1")
        #expect(Set(requests.dropFirst().dropLast().map(\.path)) == Set([
            "/api/v1/upload-sessions/thumbnail-session/complete",
            "/api/v1/upload-sessions/model-session/complete"
        ]))
        assertCreateScanBody(requests[0].body, expectedMesh: files.meshData, expectedThumbnail: files.thumbnailData)

        let uploads = await uploadSession.requests
        #expect(Set(uploads.map(\.path)) == Set(["/thumbnail", "/model"]))
        #expect(uploads.first { $0.path == "/thumbnail" }?.body == files.thumbnailData)
        #expect(uploads.first { $0.path == "/model" }?.body == files.meshData)
        #expect(uploads.allSatisfy { $0.contentType != nil })

        let cached = try await localStore.fetchProject(id: project.id)
        #expect(cached.roomScans.contains { $0.id == "remote-scan-id" })
    }

    @Test func saveScan_doesNotPersistWhenAssetUploadFails() async throws {
        let project = ProjectSummary(id: "project-1", name: "Project")
        let localStore = MockProjectsService(projects: [project], simulatedDelayNanoseconds: 0)
        let recorder = SaveScanHTTPRecorder()
        let httpClient = FakeHTTPClient { endpoint in
            await recorder.record(endpoint)
            if endpoint.path == "/api/v1/projects/project-1/scans" {
                return .success(RemoteProjectsServiceFixtures.createScanJSON())
            }
            if endpoint.path == "/api/v1/upload-sessions/thumbnail-session/complete" {
                return .success(Data("{}".utf8))
            }
            if endpoint.path == "/api/v1/upload-sessions/model-session/fail" {
                return .success(Data("{}".utf8))
            }
            if endpoint.path == "/api/v1/scans/remote-scan-id" {
                return .success(Data("{}".utf8))
            }
            Issue.record("Unexpected endpoint after a failed upload: \(endpoint.path)")
            return .failure(.networkError)
        }
        let uploadSession = FakeAssetUploadSession { request in
            request.url?.path == "/model" ? .failure(URLError(.cannotConnectToHost)) : .success(Data())
        }
        let service = RemoteProjectsService(
            httpClient: httpClient,
            localStore: localStore,
            uploadSession: uploadSession
        )
        let files = try makeScanFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }

        await #expect(throws: ProjectsServiceError.network) {
            _ = try await service.saveScan(
                draft: files.draft,
                name: "Remote Scan",
                projectID: project.id,
                meshURL: files.meshURL
            )
        }

        let requests = await recorder.requests
        #expect(requests.first?.path == "/api/v1/projects/project-1/scans")
        #expect(requests.contains { $0.path == "/api/v1/scans/remote-scan-id" })
        #expect(!requests.contains { $0.path == "/api/v1/projects/project-1" })
        let cached = try await localStore.fetchProject(id: project.id)
        #expect(cached.roomScans.isEmpty)
    }

    @Test func saveScan_reportsUploadFailureWhenCompletionRequestFails() async throws {
        let project = ProjectSummary(id: "project-1", name: "Project")
        let localStore = MockProjectsService(projects: [project], simulatedDelayNanoseconds: 0)
        let recorder = SaveScanHTTPRecorder()
        let httpClient = FakeHTTPClient { endpoint in
            await recorder.record(endpoint)
            switch endpoint.path {
            case "/api/v1/projects/project-1/scans":
                return .success(RemoteProjectsServiceFixtures.createScanJSON())
            case "/api/v1/upload-sessions/thumbnail-session/complete":
                return .success(Data("{}".utf8))
            case "/api/v1/upload-sessions/model-session/complete":
                return .failure(.serverError(statusCode: 500, apiError: nil))
            case "/api/v1/upload-sessions/model-session/fail":
                return .success(Data("{}".utf8))
            case "/api/v1/scans/remote-scan-id":
                return .success(Data("{}".utf8))
            default:
                Issue.record("Unexpected endpoint: \(endpoint.path)")
                return .failure(.networkError)
            }
        }
        let uploadSession = FakeAssetUploadSession { _ in .success(Data()) }
        let service = RemoteProjectsService(
            httpClient: httpClient,
            localStore: localStore,
            uploadSession: uploadSession
        )
        let files = try makeScanFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }

        await #expect(throws: ProjectsServiceError.network) {
            _ = try await service.saveScan(
                draft: files.draft,
                name: "Remote Scan",
                projectID: project.id,
                meshURL: files.meshURL
            )
        }

        let requests = await recorder.requests
        #expect(requests.contains { $0.path == "/api/v1/upload-sessions/model-session/fail" })
        #expect(!requests.contains { $0.path == "/api/v1/projects/project-1" })
    }

    @Test func saveScan_rejectsEmptyLocalAssetsWithoutCreatingRemoteScan() async throws {
        let project = ProjectSummary(id: "project-1", name: "Project")
        let recorder = SaveScanHTTPRecorder()
        let httpClient = FakeHTTPClient { endpoint in
            await recorder.record(endpoint)
            Issue.record("HTTP should not be called for empty local assets: \(endpoint.path)")
            return .failure(.networkError)
        }
        let service = RemoteProjectsService(
            httpClient: httpClient,
            localStore: MockProjectsService(projects: [project], simulatedDelayNanoseconds: 0),
            uploadSession: FakeAssetUploadSession { _ in .success(Data()) }
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteProjectsServiceEmptyAssets_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let meshURL = directory.appendingPathComponent("mesh.usdz")
        let thumbnailURL = directory.appendingPathComponent("thumbnail.jpg")
        try Data("thumbnail bytes".utf8).write(to: thumbnailURL)
        try Data().write(to: meshURL)

        let draft = RoomScanDraft(
            id: "local-draft-id",
            meshFileURL: meshURL,
            thumbnailFileURL: thumbnailURL
        )

        await #expect(throws: ProjectsServiceError.network) {
            _ = try await service.saveScan(
                draft: draft,
                name: "Remote Scan",
                projectID: project.id,
                meshURL: meshURL
            )
        }

        let requests = await recorder.requests
        #expect(requests.isEmpty)
    }

    @Test func retryScanUpload_createsAssetSessionsAndUploadsBothLocalAssets() async throws {
        let files = try makeScanFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }

        let failedScan = RoomScanSummary(
            id: "failed-scan",
            name: "Retry me",
            createdAt: files.draft.createdAt,
            localModelURL: files.meshURL,
            thumbnailName: "thumbnail.jpg",
            syncStatus: .failed,
            notes: []
        )
        let project = ProjectSummary(id: "project-1", name: "Project", roomScans: [failedScan])
        let localStore = MockProjectsService(projects: [project], simulatedDelayNanoseconds: 0)
        let recorder = SaveScanHTTPRecorder()
        let httpClient = FakeHTTPClient { endpoint in
            await recorder.record(endpoint)
            switch endpoint.path {
            case "/api/v1/scans/failed-scan/assets/upload-sessions":
                guard let body = endpoint.body,
                      let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                      let assetType = payload["assetType"] as? String
                else {
                    return .failure(.decodingError(underlying: "test", bodyPreview: ""))
                }
                let response = assetType == "MODEL"
                    ? RemoteProjectsServiceFixtures.retryUploadSessionJSON(
                        sessionID: "retry-model-session",
                        uploadPath: "retry-model"
                    )
                    : RemoteProjectsServiceFixtures.retryUploadSessionJSON(
                        sessionID: "retry-thumbnail-session",
                        uploadPath: "retry-thumbnail"
                    )
                return .success(response)
            case "/api/v1/upload-sessions/retry-model-session/complete",
                 "/api/v1/upload-sessions/retry-thumbnail-session/complete":
                return .success(Data("{}".utf8))
            case "/api/v1/projects/project-1":
                return .success(RemoteProjectsServiceFixtures.sampleProjectJSON(
                    id: "project-1",
                    name: "Project",
                    description: nil,
                    scansJSON: """
                    [{
                      "id": "failed-scan", "name": "Retry me", "description": null,
                      "thumbnail": null, "noteCount": 0, "assetStatus": "READY",
                      "syncStatus": "SYNCED", "createdAt": "2026-08-11T02:56:32.757Z"
                    }]
                    """,
                    scanCount: 1
                ))
            default:
                Issue.record("Unexpected HTTP endpoint: \(endpoint.path)")
                return .failure(.networkError)
            }
        }
        let uploadSession = FakeAssetUploadSession { _ in .success(Data()) }
        let service = RemoteProjectsService(
            httpClient: httpClient,
            localStore: localStore,
            uploadSession: uploadSession
        )

        let retried = try await service.retryScanUpload(projectID: "project-1", scanID: "failed-scan")

        #expect(retried.syncStatus == .synced)
        let requests = await recorder.requests
        let sessionRequests = requests.filter { $0.path == "/api/v1/scans/failed-scan/assets/upload-sessions" }
        #expect(sessionRequests.count == 2)
        let assetTypes = Set(sessionRequests.compactMap { request -> String? in
            guard let body = request.body,
                  let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            else { return nil }
            return payload["assetType"] as? String
        })
        #expect(assetTypes == Set(["MODEL", "THUMBNAIL"]))

        let uploads = await uploadSession.requests
        #expect(Set(uploads.map(\.path)) == Set(["/retry-model", "/retry-thumbnail"]))
    }

    @Test func createScan_mapsMissingProjectToProjectNotFound() async throws {
        let project = ProjectSummary(id: "project-1", name: "Project")
        let httpClient = FakeHTTPClient { endpoint in
            #expect(endpoint.path == "/api/v1/projects/project-1/scans")
            return .failure(.serverError(statusCode: 404, apiError: nil))
        }
        let service = RemoteProjectsService(
            httpClient: httpClient,
            localStore: MockProjectsService(projects: [project], simulatedDelayNanoseconds: 0)
        )
        let files = try makeScanFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }

        await #expect(throws: ProjectsServiceError.projectNotFound) {
            _ = try await service.saveScan(
                draft: files.draft,
                name: "Kitchen",
                projectID: project.id,
                meshURL: files.meshURL
            )
        }
    }

    @Test func createScan_mapsValidationToInvalidScanName() async throws {
        let project = ProjectSummary(id: "project-1", name: "Project")
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
            localStore: MockProjectsService(projects: [project], simulatedDelayNanoseconds: 0)
        )
        let files = try makeScanFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }

        await #expect(throws: ProjectsServiceError.invalidScanName) {
            _ = try await service.saveScan(
                draft: files.draft,
                name: "Kitchen",
                projectID: project.id,
                meshURL: files.meshURL
            )
        }
    }

    private func makeScanFiles() throws -> ScanFiles {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteProjectsServiceSaveScan_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let meshURL = directory.appendingPathComponent("mesh.usdz")
        let thumbnailURL = directory.appendingPathComponent("thumbnail.jpg")
        let meshData = Data("model bytes".utf8)
        let thumbnailData = Data("thumbnail bytes".utf8)
        try meshData.write(to: meshURL)
        try thumbnailData.write(to: thumbnailURL)
        return ScanFiles(
            directory: directory,
            draft: RoomScanDraft(id: "local-draft-id", meshFileURL: meshURL, thumbnailFileURL: thumbnailURL),
            meshURL: meshURL,
            meshData: meshData,
            thumbnailData: thumbnailData
        )
    }

    private func assertCreateScanBody(_ body: Data?, expectedMesh: Data, expectedThumbnail: Data) {
        guard let body,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let scanFile = object["scanFile"] as? [String: Any],
              let thumbnail = object["thumbnail"] as? [String: Any]
        else {
            Issue.record("Expected create-scan JSON body")
            return
        }
        #expect(object["name"] as? String == "Remote Scan")
        #expect(scanFile["contentType"] as? String == "model/usdz")
        #expect(scanFile["sizeBytes"] as? Int == expectedMesh.count)
        #expect(scanFile["checksum"] as? String == "9cb7487000bc86ac36ce83c4acfabe8878552be99572a6770f65ab1d048a5c48")
        #expect(thumbnail["contentType"] as? String == "image/jpeg")
        #expect(thumbnail["sizeBytes"] as? Int == expectedThumbnail.count)
    }
}

private struct ScanFiles {
    let directory: URL
    let draft: RoomScanDraft
    let meshURL: URL
    let meshData: Data
    let thumbnailData: Data
}

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

    @Test func fetchProjects_mapsValidationToNetwork() async {
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

        await #expect(throws: ProjectsServiceError.network) {
            _ = try await service.fetchProjects(page: 1, pageSize: 10)
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

    @Test func deleteScan_mapsNotFound() async {
        let httpClient = FakeHTTPClient { endpoint in
            #expect(endpoint.path == "/api/v1/scans/missing-scan")
            #expect(endpoint.method == .delete)
            return .failure(.serverError(statusCode: 404, apiError: nil))
        }
        let service = RemoteProjectsService(
            httpClient: httpClient,
            localStore: MockProjectsService(projects: [], simulatedDelayNanoseconds: 0)
        )

        await #expect(throws: ProjectsServiceError.notFound) {
            try await service.deleteScan(projectID: "project-1", scanID: "missing-scan")
        }
    }
}

private enum RemoteProjectsServiceFixtures {
    nonisolated static func createScanJSON() -> Data {
        Data(
            """
            {
              "id": "remote-scan-id",
              "uploads": {
                "thumbnail": {
                  "uploadSessionId": "thumbnail-session",
                  "uploadUrl": "https://uploads.example.com/thumbnail"
                },
                "scanFile": {
                  "uploadSessionId": "model-session",
                  "uploadUrl": "https://uploads.example.com/model"
                }
              }
            }
            """.utf8
        )
    }

    nonisolated static func retryUploadSessionJSON(sessionID: String, uploadPath: String) -> Data {
        Data(
            """
            {
              "uploadSessionId": "\(sessionID)",
              "assetId": "asset-\(sessionID)",
              "assetType": "MODEL",
              "status": "PENDING",
              "uploadUrl": "https://uploads.example.com/\(uploadPath)",
              "uploadUrlExpiresAt": "2026-08-14T08:00:44.375Z"
            }
            """.utf8
        )
    }

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

private actor SaveScanHTTPRecorder {
    private(set) var requests: [APIEndpoint] = []

    func record(_ endpoint: APIEndpoint) {
        requests.append(endpoint)
    }
}

private struct UploadedRequest: Equatable, Sendable {
    let path: String
    let body: Data?
    let contentType: String?
}

private actor FakeAssetUploadSession: AssetUploadSession {
    private let handler: @Sendable (URLRequest) -> Result<Data, Error>
    private(set) var requests: [UploadedRequest] = []

    init(handler: @escaping @Sendable (URLRequest) -> Result<Data, Error>) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url else { throw URLError(.badURL) }
        requests.append(UploadedRequest(
            path: url.path,
            body: request.httpBody,
            contentType: request.value(forHTTPHeaderField: "Content-Type")
        ))
        switch handler(request) {
        case .success(let data):
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        case .failure(let error):
            throw error
        }
    }
}
