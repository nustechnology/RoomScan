//
//  RemoteProjectsService.swift
//  roomscan
//

import Foundation

protocol AssetUploadSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: AssetUploadSession {}

/// Network-backed projects service for list/detail/create/update/delete.
/// Other operations stay on the local cache for now.
final class RemoteProjectsService: ProjectsService, ScanAssetRetrying, @unchecked Sendable {
    let httpClient: any HTTPClient
    let localStore: any ProjectsLocalCache
    let uploadSession: any AssetUploadSession
    let revisionStore = APIRevisionStore.shared

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
            for project in response.items {
                await revisionStore.update(project.revision.map(String.init), for: project.id)
                for scan in project.scans ?? [] {
                    await revisionStore.update(scan.revision.map(String.init), for: scan.id)
                }
            }
            var projects: [ProjectSummary] = []
            projects.reserveCapacity(response.items.count)
            for item in response.items {
                let existingScans = (try? await localStore.fetchProject(id: item.id))?.roomScans ?? []
                let project = ProjectAPIMapping.toProjectSummary(
                    item,
                    revision: Int(await revisionStore.currentRevision(for: item.id)),
                    preservingRoomScans: existingScans
                )
                try await cacheLocally(project)
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
            throw mapHTTPClientError(error, operation: .fetchProjects)
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
            await revisionStore.update(response.revision.map(String.init), for: id)
            for scan in response.scans ?? [] {
                await revisionStore.update(scan.revision.map(String.init), for: scan.id)
            }
            let existingScans = (try? await localStore.fetchProject(id: id))?.roomScans ?? []
            let project = ProjectAPIMapping.toProjectSummary(
                response,
                revision: Int(await revisionStore.currentRevision(for: id)),
                preservingRoomScans: existingScans
            )
            try await cacheLocally(project)
            return project
        } catch let error as HTTPClientError {
            #if DEBUG
            logHTTPClientError("fetchProject", error)
            #endif
            throw mapHTTPClientError(error, operation: .fetchProject)
        } catch {
            #if DEBUG
            print("[RemoteProjectsService] fetchProject failed: unexpected \(error)")
            #endif
            throw ProjectsServiceError.network
        }
    }

    func updateProject(id: String, name: String, description: String, revision: Int = 1) async throws -> ProjectSummary {
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
            body: body,
            revision: String(revision)
        )

        #if DEBUG
        print(
            """
            [RemoteProjectsService] updateProject request method=\(endpoint.method.rawValue) \
            path=\(endpoint.path) bodyBytes=\(body.count)
            """
        )
        #endif

        do {
            let response: ProjectAPIResponse = try await httpClient.request(endpoint)
            await revisionStore.update(response.revision.map(String.init), for: id)
            let existingScans = (try? await localStore.fetchProject(id: id))?.roomScans ?? []
            let project = ProjectAPIMapping.toProjectSummary(
                response,
                revision: Int(await revisionStore.currentRevision(for: id)),
                preservingRoomScans: existingScans
            )
            try await cacheLocally(project)
            return project
        } catch let error as HTTPClientError {
            #if DEBUG
            logHTTPClientError("updateProject", error)
            #endif
            throw mapHTTPClientError(error, operation: .updateProject)
        } catch {
            #if DEBUG
            print("[RemoteProjectsService] updateProject failed: unexpected \(error)")
            #endif
            throw ProjectsServiceError.network
        }
    }

    func deleteProject(id: String) async throws {
        let revision = await revisionStore.currentRevision(for: id)
        let endpoint = APIEndpoint(
            path: "/api/v1/projects/\(id)",
            method: .delete,
            revision: revision
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
            await revisionStore.advance(for: id)
            try await localStore.deleteProject(id: id)
        } catch let error as HTTPClientError {
            #if DEBUG
            logHTTPClientError("deleteProject", error)
            #endif
            throw mapHTTPClientError(error, operation: .deleteProject)
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

        let idempotencyKey = UUID().uuidString
        let endpoint = APIEndpoint(
            path: "/api/v1/projects",
            method: .post,
            body: body,
            idempotencyKey: idempotencyKey
        )

        #if DEBUG
        print(
            """
            [RemoteProjectsService] createProject request method=\(endpoint.method.rawValue) \
            path=\(endpoint.path) bodyBytes=\(body.count)
            """
        )
        #endif

        do {
            return try await performCreateProject(endpoint: endpoint)
        } catch let error as HTTPClientError where error == .networkError {
            // Retry once with the same Idempotency-Key so a committed create is not duplicated.
            do {
                return try await performCreateProject(endpoint: endpoint)
            } catch let retryError as HTTPClientError {
                #if DEBUG
                logHTTPClientError("createProject", retryError)
                #endif
                throw mapHTTPClientError(retryError, operation: .createProject)
            } catch {
                throw ProjectsServiceError.network
            }
        } catch let error as HTTPClientError {
            #if DEBUG
            logHTTPClientError("createProject", error)
            #endif
            throw mapHTTPClientError(error, operation: .createProject)
        } catch {
            #if DEBUG
            print("[RemoteProjectsService] createProject failed: unexpected \(error)")
            #endif
            throw ProjectsServiceError.network
        }
    }
}
