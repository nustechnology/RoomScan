//
//  RemoteSharedService.swift
//  roomscan
//

import Foundation

actor RemoteSharedService: SharedService {
    private static let maximumPageCount = 100

    private let httpClient: any HTTPClient
    private let now: @Sendable () -> Date
    private var locallyIngestedProjects: [String: SharedProjectItem] = [:]
    private var locallyIngestedScans: [String: SharedScanItem] = [:]
    private var projectNamesByID: [String: String] = [:]

    init(
        httpClient: any HTTPClient,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.httpClient = httpClient
        self.now = now
    }

    func fetchSharedProjects() async throws -> [SharedProjectItem] {
        do {
            let remoteProjects = try await fetchAllSharedProjects()
            projectNamesByID = Dictionary(
                remoteProjects.map { ($0.id, $0.name) },
                uniquingKeysWith: { _, candidate in candidate }
            )
            let remoteItems = remoteProjects.map(SharedProjectAPIItem.toSharedProjectItem)
            var itemsByID = Dictionary(
                remoteItems.map { ($0.id, $0) },
                uniquingKeysWith: { current, candidate in
                    candidate.statusChangedAt > current.statusChangedAt ? candidate : current
                }
            )

            for (id, item) in locallyIngestedProjects {
                guard let remoteItem = itemsByID[id] else {
                    itemsByID[id] = item
                    continue
                }

                guard remoteItem.status.isActive,
                      item.statusChangedAt > remoteItem.statusChangedAt else {
                    continue
                }

                itemsByID[id] = item
            }

            let currentDate = now()
            return itemsByID.values
                .filter {
                    SharedInactiveRetention.shouldRetain(
                        status: $0.status,
                        statusChangedAt: $0.statusChangedAt,
                        now: currentDate
                    )
                }
                .sorted { $0.statusChangedAt > $1.statusChangedAt }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as HTTPClientError {
            throw mapHTTPError(error)
        } catch {
            throw SharedServiceError.network
        }
    }

    func fetchSharedScans() async throws -> [SharedScanItem] {
        do {
            let remoteScans = try await fetchAllSharedScans()
            let remoteProjects = try await fetchAllSharedProjects()
            let fetchedProjectNames = Dictionary(
                remoteProjects.map { ($0.id, $0.name) },
                uniquingKeysWith: { _, candidate in candidate }
            )
            projectNamesByID.merge(fetchedProjectNames, uniquingKeysWith: { _, candidate in candidate })
            let remoteItems = remoteScans.map {
                SharedScanAPIItem.toSharedScanItem(
                    $0,
                    projectName: projectNamesByID[$0.projectId] ?? "Unknown Project"
                )
            }
            var itemsByID = Dictionary(
                remoteItems.map { ($0.id, $0) },
                uniquingKeysWith: { current, candidate in
                    candidate.statusChangedAt > current.statusChangedAt ? candidate : current
                }
            )

            for (id, item) in locallyIngestedScans {
                guard let remoteItem = itemsByID[id] else {
                    itemsByID[id] = item
                    continue
                }

                guard remoteItem.status.isActive,
                      item.statusChangedAt > remoteItem.statusChangedAt else {
                    continue
                }

                itemsByID[id] = item
            }

            let currentDate = now()
            return itemsByID.values
                .filter {
                    SharedInactiveRetention.shouldRetain(
                        status: $0.status,
                        statusChangedAt: $0.statusChangedAt,
                        now: currentDate
                    )
                }
                .sorted { $0.statusChangedAt > $1.statusChangedAt }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as HTTPClientError {
            throw mapHTTPError(error)
        } catch {
            throw SharedServiceError.network
        }
    }

    func removeSharedItem(id: String, scope: SharedItemScope) async throws {
        let path: String
        switch scope {
        case .project:
            path = "/api/v1/shared-projects/\(id)"
        case .scan:
            path = "/api/v1/shared-scans/\(id)"
        }

        do {
            let _: EmptyAPIResponse = try await httpClient.request(
                APIEndpoint(path: path, method: .delete)
            )
            switch scope {
            case .project:
                locallyIngestedProjects.removeValue(forKey: id)
            case .scan:
                locallyIngestedScans.removeValue(forKey: id)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as HTTPClientError {
            throw mapHTTPError(error)
        } catch {
            throw SharedServiceError.network
        }
    }

    func ingestSharedProject(_ project: SharedProjectItem) async throws {
        locallyIngestedProjects[project.id] = project
    }

    func ingestSharedScan(_ scan: SharedScanItem) async throws {
        locallyIngestedScans[scan.id] = scan
    }

    private func fetchAllSharedProjects() async throws -> [SharedProjectAPIItem] {
        var projects: [SharedProjectAPIItem] = []

        for page in 1...Self.maximumPageCount {
            try Task.checkCancellation()

            let response: SharedProjectsListAPIResponse = try await httpClient.request(
                paginatedEndpoint(path: "/api/v1/shared-projects", page: page)
            )
            projects.append(contentsOf: response.items)

            guard !response.items.isEmpty, page < response.pagination.totalPages else {
                return projects
            }
        }

        return projects
    }

    private func fetchAllSharedScans() async throws -> [SharedScanAPIItem] {
        var scans: [SharedScanAPIItem] = []

        for page in 1...Self.maximumPageCount {
            try Task.checkCancellation()

            let response: SharedScansListAPIResponse = try await httpClient.request(
                paginatedEndpoint(path: "/api/v1/shared-scans", page: page)
            )
            scans.append(contentsOf: response.items)

            guard !response.items.isEmpty, page < response.pagination.totalPages else {
                return scans
            }
        }

        return scans
    }

    private func paginatedEndpoint(path: String, page: Int) -> APIEndpoint {
        APIEndpoint(
            path: path,
            method: .get,
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "limit", value: "50"),
                URLQueryItem(name: "sort", value: "updatedAt:desc")
            ]
        )
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

private struct SharedScansListAPIResponse: Decodable, Sendable {
    let items: [SharedScanAPIItem]
    let pagination: ProjectsPaginationDTO
}

private struct SharedPermissionsDTO: Decodable, Sendable {
    let canView: Bool
}

private struct SharedProjectAPIItem: Decodable, Sendable {
    let id: String
    let name: String
    let owner: ProjectOwnerDTO
    let scanCount: Int
    let thumbnail: String?
    let updatedAt: Date
    let status: String
    let permissions: SharedPermissionsDTO

    static func toSharedProjectItem(_ item: SharedProjectAPIItem) -> SharedProjectItem {
        let ownerName = item.owner.email?.isEmpty == false ? item.owner.email! : "Unknown"
        let accessStatus = SharedAccessStatus.fromAPI(item.status)
        return SharedProjectItem(
            id: item.id,
            name: item.name,
            ownerName: ownerName,
            scanCount: max(0, item.scanCount),
            thumbnailName: item.thumbnail,
            status: accessStatus,
            statusChangedAt: item.updatedAt,
            detailProject: accessStatus.isActive ? ProjectSummary(
                id: item.id,
                name: item.name,
                ownerName: ownerName,
                updatedAt: item.updatedAt,
                scanCount: max(0, item.scanCount)
            ) : nil
        )
    }
}

private struct SharedScanAPIItem: Decodable, Sendable {
    let id: String
    let projectId: String
    let name: String
    let thumbnail: String?
    let creator: ProjectOwnerDTO
    let noteCount: Int
    let syncStatus: String?
    let updatedAt: Date
    let status: String
    let permissions: SharedPermissionsDTO

    static func toSharedScanItem(_ item: SharedScanAPIItem, projectName: String) -> SharedScanItem {
        let ownerName = item.creator.email?.isEmpty == false ? item.creator.email! : "Unknown"
        let accessStatus = SharedAccessStatus.fromAPI(item.status)
        let scan = RoomScanSummary(
            id: item.id,
            name: item.name,
            createdAt: item.updatedAt,
            thumbnailName: "",
            syncStatus: RoomScanSyncStatus.fromAPI(item.syncStatus),
            creatorUserID: item.creator.id,
            creatorDisplayName: ownerName,
            notes: [],
            thumbnailPath: item.thumbnail ?? "",
            noteCount: max(0, item.noteCount)
        )

        return SharedScanItem(
            id: item.id,
            name: item.name,
            ownerName: ownerName,
            noteCount: max(0, item.noteCount),
            projectID: item.projectId,
            projectName: projectName,
            thumbnailName: item.thumbnail,
            status: accessStatus,
            statusChangedAt: item.updatedAt,
            detailScan: accessStatus.isActive ? scan : nil
        )
    }
}

private extension SharedAccessStatus {
    static func fromAPI(_ status: String) -> SharedAccessStatus {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "ACTIVE":
            return .active
        case "REVOKED", "ACCESS_REVOKED":
            return .accessRevoked
        case "DELETED", "ITEM_DELETED", "PROJECT_DELETED":
            return .itemDeleted
        default:
            return .itemDeleted
        }
    }
}
