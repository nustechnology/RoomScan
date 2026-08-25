//
//  RemoteProjectsService+Helpers.swift
//  roomscan
//

import Foundation

extension RemoteProjectsService {
    func performCreateProject(
        endpoint: APIEndpoint
    ) async throws -> ProjectSummary {
        let response: ProjectAPIResponse = try await httpClient.request(endpoint)
        await revisionStore.update(response.revision.map(String.init), for: response.id)
        let project = ProjectAPIMapping.toProjectSummary(
            response,
            revision: Int(await revisionStore.currentRevision(for: response.id))
        )
        try await cacheLocally(project)
        return project
    }

    /// Persist after a successful REST call. Disk errors do not fail the request.
    func cacheLocally(_ project: ProjectSummary) async throws {
        do {
            try await localStore.cacheProject(project)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            #if DEBUG
            print("[RemoteProjectsService] cacheProject failed: \(error)")
            #endif
        }
    }

    #if DEBUG
    func logHTTPClientError(_ operation: String, _ error: HTTPClientError) {
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
                underlying=\(underlying) bodyBytes=\(bodyPreview.utf8.count)
                """
            )
        }
    }
    #endif
}
