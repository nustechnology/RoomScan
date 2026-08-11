//
//  RemoteProjectsService.swift
//  roomscan
//

import Foundation

/// Network-backed projects service for list/detail/create/update/delete.
/// Other operations stay on the local cache for now.
final class RemoteProjectsService: ProjectsService, @unchecked Sendable {
    private let httpClient: any HTTPClient
    private let localStore: any ProjectsLocalCache

    init(
        httpClient: any HTTPClient,
        localStore: any ProjectsLocalCache
    ) {
        self.httpClient = httpClient
        self.localStore = localStore
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

        #if DEBUG
        print(
            """
            [RemoteProjectsService] fetchProjects request method=\(endpoint.method.rawValue) \
            path=\(endpoint.path) page=\(page) limit=\(pageSize)
            """
        )
        #endif

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

        #if DEBUG
        print(
            """
            [RemoteProjectsService] fetchProject request method=\(endpoint.method.rawValue) \
            path=\(endpoint.path)
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

    func saveScan(
        draft: RoomScanDraft,
        name: String,
        projectID: String,
        meshURL: URL
    ) async throws -> RoomScanSummary {
        try await localStore.saveScan(draft: draft, name: name, projectID: projectID, meshURL: meshURL)
    }

    func renameScan(projectID: String, scanID: String, name: String) async throws -> RoomScanSummary {
        try await localStore.renameScan(projectID: projectID, scanID: scanID, name: name)
    }

    func deleteScan(projectID: String, scanID: String) async throws {
        try await localStore.deleteScan(projectID: projectID, scanID: scanID)
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
