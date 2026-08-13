//
//  RemoteProjectsService.swift
//  roomscan
//

import CryptoKit
import Foundation

protocol AssetUploadSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: AssetUploadSession {}

/// Network-backed projects service for list/detail/create/update/delete.
/// Other operations stay on the local cache for now.
final class RemoteProjectsService: ProjectsService, @unchecked Sendable {
    private let httpClient: any HTTPClient
    private let localStore: any ProjectsLocalCache
    private let uploadSession: any AssetUploadSession

    init(
        httpClient: any HTTPClient,
        localStore: any ProjectsLocalCache,
        uploadSession: any AssetUploadSession = URLSession.shared
    ) {
        self.httpClient = httpClient
        self.localStore = localStore
        self.uploadSession = uploadSession
    }

    func fetchProjects(page: Int, pageSize: Int) async throws -> ProjectPage {
        guard page >= 1, pageSize > 0 else {
            throw ProjectsServiceError.invalidPagination
        }

        let endpoint = APIEndpoint(
            path: "/api/v1/projects",
            method: .get,
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "sort", value: "updatedAt:desc")
            ]
        )

        do {
            let response: ProjectsListAPIResponse = try await httpClient.request(endpoint)
            var projects: [ProjectSummary] = []
            projects.reserveCapacity(response.items.count)
            for item in response.items {
                let existingScans = (try? await localStore.fetchProject(id: item.id))?.roomScans ?? []
                let project = ProjectAPIMapping.toProjectSummary(
                    item,
                    preservingRoomScans: existingScans
                )
                await localStore.cacheProject(project)
                projects.append(project)
            }
            let hasMore = response.pagination.page < response.pagination.totalPages
            return ProjectPage(projects: projects, hasMore: hasMore)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as HTTPClientError {
            #if DEBUG
            logHTTPClientError("fetchProjects", error)
            #endif
            throw mapHTTPClientError(error)
        } catch {
            #if DEBUG
            print("[RemoteProjectsService] fetchProjects failed: unexpected \(error)")
            #endif
            throw ProjectsServiceError.network
        }
    }

    func fetchProject(id: String) async throws -> ProjectSummary {
        let endpoint = APIEndpoint(
            path: "/api/v1/projects/\(id)",
            method: .get
        )

        do {
            let response: ProjectAPIResponse = try await httpClient.request(endpoint)
            let existingScans = (try? await localStore.fetchProject(id: id))?.roomScans ?? []
            let project = ProjectAPIMapping.toProjectSummary(
                response,
                preservingRoomScans: existingScans
            )
            await localStore.cacheProject(project)
            return project
        } catch let error as HTTPClientError {
            #if DEBUG
            logHTTPClientError("fetchProject", error)
            #endif
            throw mapHTTPClientError(error)
        } catch {
            #if DEBUG
            print("[RemoteProjectsService] fetchProject failed: unexpected \(error)")
            #endif
            throw ProjectsServiceError.network
        }
    }

    func updateProject(id: String, name: String, description: String) async throws -> ProjectSummary {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...50).contains(trimmedName.count) else {
            throw ProjectsServiceError.invalidProjectName
        }
        guard trimmedDescription.count <= 500 else {
            throw ProjectsServiceError.invalidProjectName
        }

        let requestBody = UpdateProjectAPIRequest(
            name: trimmedName,
            projectDescription: trimmedDescription.isEmpty ? nil : trimmedDescription
        )
        let body: Data
        do {
            body = try JSONEncoder().encode(requestBody)
        } catch {
            #if DEBUG
            print("[RemoteProjectsService] updateProject encode failed: \(error)")
            #endif
            throw ProjectsServiceError.network
        }

        let endpoint = APIEndpoint(
            path: "/api/v1/projects/\(id)",
            method: .patch,
            body: body
        )

        #if DEBUG
        let bodyString = String(data: body, encoding: .utf8) ?? "<non-utf8 \(body.count) bytes>"
        print(
            """
            [RemoteProjectsService] updateProject request method=\(endpoint.method.rawValue) \
            path=\(endpoint.path) body=\(bodyString)
            """
        )
        #endif

        do {
            let response: ProjectAPIResponse = try await httpClient.request(endpoint)
            let existingScans = (try? await localStore.fetchProject(id: id))?.roomScans ?? []
            let project = ProjectAPIMapping.toProjectSummary(
                response,
                preservingRoomScans: existingScans
            )
            await localStore.cacheProject(project)
            return project
        } catch let error as HTTPClientError {
            #if DEBUG
            logHTTPClientError("updateProject", error)
            #endif
            throw mapHTTPClientError(error)
        } catch {
            #if DEBUG
            print("[RemoteProjectsService] updateProject failed: unexpected \(error)")
            #endif
            throw ProjectsServiceError.network
        }
    }

    func deleteProject(id: String) async throws {
        let endpoint = APIEndpoint(
            path: "/api/v1/projects/\(id)",
            method: .delete
        )

        #if DEBUG
        print(
            """
            [RemoteProjectsService] deleteProject request method=\(endpoint.method.rawValue) \
            path=\(endpoint.path)
            """
        )
        #endif

        do {
            let _: EmptyAPIResponse = try await httpClient.request(endpoint)
            try await localStore.deleteProject(id: id)
        } catch let error as HTTPClientError {
            #if DEBUG
            logHTTPClientError("deleteProject", error)
            #endif
            throw mapHTTPClientError(error)
        } catch let error as ProjectsServiceError {
            // Local cache miss after successful remote delete should not fail the call.
            if case .projectNotFound = error {
                return
            }
            throw error
        } catch {
            #if DEBUG
            print("[RemoteProjectsService] deleteProject failed: unexpected \(error)")
            #endif
            throw ProjectsServiceError.network
        }
    }

    func fetchAllProjectsSortedByUpdated() async throws -> [ProjectSummary] {
        try await localStore.fetchAllProjectsSortedByUpdated()
    }

    func createProject(name: String, projectDescription: String) async throws -> ProjectSummary {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = projectDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...50).contains(trimmedName.count) else {
            throw ProjectsServiceError.invalidProjectName
        }
        guard trimmedDescription.count <= 500 else {
            throw ProjectsServiceError.invalidProjectName
        }

        let requestBody = CreateProjectAPIRequest(
            name: trimmedName,
            projectDescription: trimmedDescription.isEmpty ? nil : trimmedDescription
        )
        let body: Data
        do {
            body = try JSONEncoder().encode(requestBody)
        } catch {
            #if DEBUG
            print("[RemoteProjectsService] createProject encode failed: \(error)")
            #endif
            throw ProjectsServiceError.network
        }

        let endpoint = APIEndpoint(
            path: "/api/v1/projects",
            method: .post,
            body: body
        )

        #if DEBUG
        let bodyString = String(data: body, encoding: .utf8) ?? "<non-utf8 \(body.count) bytes>"
        print(
            """
            [RemoteProjectsService] createProject request method=\(endpoint.method.rawValue) \
            path=\(endpoint.path) body=\(bodyString)
            """
        )
        #endif

        do {
            let response: ProjectAPIResponse = try await httpClient.request(endpoint)
            let project = ProjectAPIMapping.toProjectSummary(response)
            await localStore.cacheProject(project)
            return project
        } catch let error as HTTPClientError {
            #if DEBUG
            logHTTPClientError("createProject", error)
            #endif
            throw mapHTTPClientError(error)
        } catch {
            #if DEBUG
            print("[RemoteProjectsService] createProject failed: unexpected \(error)")
            #endif
            throw ProjectsServiceError.network
        }
    }

    func isScanNameDuplicate(name: String, projectID: String) async throws -> Bool {
        try await localStore.isScanNameDuplicate(name: name, projectID: projectID)
    }

    func renameScan(projectID: String, scanID: String, name: String) async throws -> RoomScanSummary {
        try await localStore.renameScan(projectID: projectID, scanID: scanID, name: name)
    }

    func deleteScan(projectID: String, scanID: String) async throws {
        do {
            let _: EmptyAPIResponse = try await httpClient.request(
                APIEndpoint(path: "/api/v1/scans/\(scanID)", method: .delete)
            )
            // The server is the source of truth. A stale local cache must not
            // turn a successful remote deletion into a UI failure.
            try? await localStore.deleteScan(projectID: projectID, scanID: scanID)
        } catch let error as HTTPClientError {
            throw mapHTTPClientError(error)
        }
    }

    func retryScanUpload(projectID: String, scanID: String) async throws -> RoomScanSummary {
        try await localStore.retryScanUpload(projectID: projectID, scanID: scanID)
    }

    private func mapHTTPClientError(_ error: HTTPClientError) -> ProjectsServiceError {
        switch error {
        case .networkError, .invalidURL, .decodingError:
            return .network
        case .serverError(let statusCode, _):
            switch statusCode {
            case 400:
                return .invalidProjectName
            case 404:
                return .projectNotFound
            default:
                return .network
            }
        }
    }

    #if DEBUG
    private func logHTTPClientError(_ operation: String, _ error: HTTPClientError) {
        switch error {
        case .invalidURL:
            print("[RemoteProjectsService] \(operation) failed: invalidURL")
        case .networkError:
            print("[RemoteProjectsService] \(operation) failed: networkError")
        case let .serverError(statusCode, apiError):
            print(
                """
                [RemoteProjectsService] \(operation) failed: serverError \
                status=\(statusCode) apiError=\(String(describing: apiError))
                """
            )
        case let .decodingError(underlying, bodyPreview):
            print(
                """
                [RemoteProjectsService] \(operation) failed: decodingError \
                underlying=\(underlying) body=\(bodyPreview)
                """
            )
        }
    }
    #endif
}

extension RemoteProjectsService {
    func saveScan(
        draft: RoomScanDraft,
        name: String,
        projectID: String,
        meshURL: URL
    ) async throws -> RoomScanSummary {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...50).contains(trimmedName.count) else {
            throw ProjectsServiceError.invalidScanName
        }

        let assets = try readScanAssets(draft: draft, meshURL: meshURL)
        let response = try await createScan(
            draft: draft,
            name: trimmedName,
            projectID: projectID,
            assets: assets
        )
        do {
            try await uploadScanAssets(response.uploads, assets: assets)
            let savedScan = try await persistCreatedScan(
                response.id,
                draft: draft,
                name: trimmedName,
                projectID: projectID,
                meshURL: meshURL
            )
            _ = try? await fetchProject(id: projectID)
            return savedScan
        } catch {
            try? await deleteScan(projectID: projectID, scanID: response.id)
            throw error
        }
    }

    private func readScanAssets(draft: RoomScanDraft, meshURL: URL) throws -> (thumbnail: Data, mesh: Data) {
        do {
            return (
                thumbnail: try Data(contentsOf: draft.thumbnailFileURL),
                mesh: try Data(contentsOf: meshURL)
            )
        } catch {
            throw ProjectsServiceError.network
        }
    }

    private func createScan(
        draft: RoomScanDraft,
        name: String,
        projectID: String,
        assets: (thumbnail: Data, mesh: Data)
    ) async throws -> CreateScanAPIResponse {
        let request = CreateScanAPIRequest(
            name: name,
            thumbnail: ScanAssetMetadataRequest(
                contentType: "image/jpeg",
                sizeBytes: assets.thumbnail.count,
                checksum: nil,
                modelVersion: nil
            ),
            scanFile: ScanAssetMetadataRequest(
                contentType: "model/usdz",
                sizeBytes: assets.mesh.count,
                checksum: Self.sha256(for: assets.mesh),
                modelVersion: "1.0"
            )
        )
        do {
            let body = try JSONEncoder().encode(request)
            return try await httpClient.request(
                APIEndpoint(path: "/api/v1/projects/\(projectID)/scans", method: .post, body: body)
            )
        } catch let error as HTTPClientError {
            throw mapHTTPClientError(error)
        } catch {
            throw ProjectsServiceError.network
        }
    }

    private func persistCreatedScan(
        _ scanID: String,
        draft: RoomScanDraft,
        name: String,
        projectID: String,
        meshURL: URL
    ) async throws -> RoomScanSummary {
        let remoteDraft = RoomScanDraft(
            id: scanID,
            createdAt: draft.createdAt,
            meshFileURL: meshURL,
            thumbnailFileURL: draft.thumbnailFileURL,
            name: name,
            projectID: projectID
        )
        return try await localStore.saveScan(
            draft: remoteDraft,
            name: name,
            projectID: projectID,
            meshURL: meshURL
        )
    }

    private func uploadScanAssets(
        _ uploads: ScanUploadURLs,
        assets: (thumbnail: Data, mesh: Data)
    ) async throws {
        async let thumbnailUpload: Void = uploadAndComplete(
            assets.thumbnail,
            contentType: "image/jpeg",
            target: uploads.thumbnail
        )
        async let meshUpload: Void = uploadAndComplete(
            assets.mesh,
            contentType: "model/usdz",
            target: uploads.scanFile
        )
        _ = try await (thumbnailUpload, meshUpload)
    }

    private func uploadAndComplete(
        _ data: Data,
        contentType: String,
        target: PresignedUploadTarget
    ) async throws {
        var request = URLRequest(url: target.uploadUrl)
        request.httpMethod = HTTPMethod.put.rawValue
        request.httpBody = data
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        let response: URLResponse
        do {
            (_, response) = try await uploadSession.data(for: request)
        } catch {
            throw ProjectsServiceError.network
        }
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ProjectsServiceError.network
        }

        let completionRequest = UploadCompletionAPIRequest(
            sizeBytes: data.count,
            checksum: contentType == "model/usdz" ? Self.sha256(for: data) : nil
        )
        let completionBody = try JSONEncoder().encode(completionRequest)
        let _: EmptyAPIResponse = try await httpClient.request(
            APIEndpoint(
                path: "/api/v1/upload-sessions/\(target.uploadSessionId)/complete",
                method: .post,
                body: completionBody
            )
        )
    }

    private static func sha256(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
