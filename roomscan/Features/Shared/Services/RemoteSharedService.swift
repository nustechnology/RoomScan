//
//  RemoteSharedService.swift
//  roomscan
//

import Foundation

/// Network-backed source for the Shared With Me projects list.
///
/// The shared-project endpoint only returns project summaries. Selecting a card
/// therefore opens the normal project detail flow, which loads the full project
/// using the same authenticated client and presents it read-only.
actor RemoteSharedService: SharedService {
    private let httpClient: any HTTPClient
    private var locallyIngestedProjects: [String: SharedProjectItem] = [:]
    private var locallyIngestedScans: [String: SharedScanItem] = [:]
    private var locallyRemovedItems: Set<String> = []

    init(httpClient: any HTTPClient) {
        self.httpClient = httpClient
    }

    func fetchSharedProjects() async throws -> [SharedProjectItem] {
        do {
            let remoteProjects = try await fetchAllSharedProjects()
            let remoteItems = remoteProjects
                .filter { $0.permissions.canView }
                .map(SharedProjectAPIItem.toSharedProjectItem)

            var itemsByID = Dictionary(
                remoteItems.map { ($0.id, $0) },
                uniquingKeysWith: { current, candidate in
                    candidate.statusChangedAt > current.statusChangedAt ? candidate : current
                }
            )
            for (id, item) in locallyIngestedProjects {
                itemsByID[id] = item
            }

            return itemsByID.values
                .filter { !locallyRemovedItems.contains($0.id) }
                .sorted { $0.statusChangedAt > $1.statusChangedAt }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as HTTPClientError {
            throw mapHTTPError(error)
        } catch {
            throw SharedServiceError.network
        }
    }

    /// The backend endpoint for shared scans has not been supplied yet, so keep
    /// invitation-ingested scans visible until that API is integrated.
    func fetchSharedScans() async throws -> [SharedScanItem] {
        locallyIngestedScans.values
            .filter { !locallyRemovedItems.contains($0.id) }
            .sorted { $0.statusChangedAt > $1.statusChangedAt }
    }

    func removeSharedItem(id: String, scope: SharedItemScope) async throws {
        switch scope {
        case .project:
            do {
                let _: EmptyAPIResponse = try await httpClient.request(
                    APIEndpoint(path: "/api/v1/shared-projects/\(id)", method: .delete)
                )
                locallyIngestedProjects.removeValue(forKey: id)
                locallyRemovedItems.insert(id)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as HTTPClientError {
                throw mapHTTPError(error)
            } catch {
                throw SharedServiceError.network
            }
        case .scan:
            // The recipient-side remove endpoint for shared scans has not been supplied yet.
            locallyRemovedItems.insert(id)
        }
    }

    func ingestSharedProject(_ project: SharedProjectItem) async throws {
        locallyRemovedItems.remove(project.id)
        locallyIngestedProjects[project.id] = project
    }

    func ingestSharedScan(_ scan: SharedScanItem) async throws {
        locallyRemovedItems.remove(scan.id)
        locallyIngestedScans[scan.id] = scan
    }

    private func fetchAllSharedProjects() async throws -> [SharedProjectAPIItem] {
        let pageSize = 50
        var page = 1
        var projects: [SharedProjectAPIItem] = []

        while true {
            let endpoint = APIEndpoint(
                path: "/api/v1/shared-projects",
                method: .get,
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "limit", value: String(pageSize)),
                    URLQueryItem(name: "sort", value: "updatedAt:desc")
                ]
            )
            let response: SharedProjectsListAPIResponse = try await httpClient.request(endpoint)
            projects.append(contentsOf: response.items)

            guard response.pagination.page < response.pagination.totalPages else { break }
            page = response.pagination.page + 1
        }

        return projects
    }

    private func mapHTTPError(_ error: HTTPClientError) -> SharedServiceError {
        switch error {
        case .serverError(let statusCode, _) where statusCode == 404:
            return .notFound
        case .invalidURL, .networkError, .decodingError, .serverError:
            return .network
        }
    }
}

private struct SharedProjectsListAPIResponse: Decodable, Sendable {
    let items: [SharedProjectAPIItem]
    let pagination: ProjectsPaginationDTO
}

private struct SharedProjectAPIItem: Decodable, Sendable {
    let id: String
    let name: String
    let owner: ProjectOwnerDTO
    let scanCount: Int
    let thumbnail: String?
    let updatedAt: Date
    let status: String
    let permissions: ProjectPermissionsDTO

    static func toSharedProjectItem(_ item: SharedProjectAPIItem) -> SharedProjectItem {
        let accessStatus: SharedAccessStatus = item.status.uppercased() == "ACTIVE" ? .active : .itemDeleted
        return SharedProjectItem(
            id: item.id,
            name: item.name,
            ownerName: item.owner.email?.isEmpty == false ? item.owner.email! : "Unknown",
            scanCount: max(0, item.scanCount),
            thumbnailName: item.thumbnail,
            status: accessStatus,
            statusChangedAt: item.updatedAt,
            detailProject: accessStatus.isActive ? ProjectSummary(
                id: item.id,
                name: item.name,
                ownerName: item.owner.email?.isEmpty == false ? item.owner.email! : "Unknown",
                updatedAt: item.updatedAt,
                scanCount: max(0, item.scanCount)
            ) : nil
        )
    }
}
