//
//  RemoteSharedServiceTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

struct RemoteSharedServiceTests {
    @Test func fetchSharedItems_mapsProjectAndScanResponses() async throws {
        let client = SharedHTTPClient { endpoint in
            switch endpoint.path {
            case "/api/v1/shared-projects":
                #expect(endpoint.method == .get)
                return .success(Self.sharedProjectsJSON)
            case "/api/v1/shared-scans":
                #expect(endpoint.method == .get)
                return .success(Self.sharedScansJSON)
            default:
                Issue.record("Unexpected endpoint: \(endpoint.path)")
                return .failure(.networkError)
            }
        }
        let service = RemoteSharedService(httpClient: client, now: { Self.fixtureNow })

        let projects = try await service.fetchSharedProjects()
        let scans = try await service.fetchSharedScans()

        #expect(projects.count == 3)
        #expect(projects[0].id == "shared-project-1")
        #expect(projects[0].ownerName == "Project Owner")
        #expect(projects[0].detailProject?.id == "shared-project-1")
        #expect(projects.first { $0.id == "shared-project-revoked" }?.status == .accessRevoked)
        #expect(projects.first { $0.id == "shared-project-revoked" }?.ownerName == "owner@example.com")
        #expect(projects.first { $0.id == "shared-project-deleted" }?.status == .itemDeleted)
        #expect(
            projects.first { $0.id == "shared-project-deleted" }?.ownerName
                == String(localized: "shared.owner.unknown")
        )
        #expect(scans.count == 2)
        #expect(scans[0].id == "shared-scan-1")
        #expect(scans[0].ownerName == "Scan Creator")
        #expect(scans[0].projectID == "shared-project-1")
        #expect(scans[0].projectName == "Shared Project")
        #expect(scans[0].noteCount == 2)
        #expect(scans[0].detailScan?.syncStatus == .synced)
        #expect(scans.first { $0.id == "shared-scan-revoked" }?.status == .accessRevoked)
        #expect(scans.first { $0.id == "shared-scan-revoked" }?.ownerName == "owner@example.com")
    }

    @Test func removeSharedItem_callsScopeSpecificEndpoints() async throws {
        let client = SharedHTTPClient { endpoint in
            #expect(endpoint.method == .delete)
            switch endpoint.path {
            case "/api/v1/shared-projects/shared-project-1",
                 "/api/v1/shared-scans/shared-scan-1":
                return .success(Data())
            default:
                Issue.record("Unexpected endpoint: \(endpoint.path)")
                return .failure(.networkError)
            }
        }
        let service = RemoteSharedService(httpClient: client, now: { Self.fixtureNow })

        try await service.removeSharedItem(id: "shared-project-1", scope: .project)
        try await service.removeSharedItem(id: "shared-scan-1", scope: .scan)
    }

    @Test func fetchSharedProjects_includesAnItemReturnedAfterRemoval() async throws {
        let client = SharedHTTPClient { endpoint in
            switch (endpoint.method, endpoint.path) {
            case (.get, "/api/v1/shared-projects"):
                return .success(Self.sharedProjectsJSON)
            case (.delete, "/api/v1/shared-projects/shared-project-1"):
                return .success(Data())
            default:
                Issue.record("Unexpected endpoint: \(endpoint.method) \(endpoint.path)")
                return .failure(.networkError)
            }
        }
        let service = RemoteSharedService(httpClient: client, now: { Self.fixtureNow })

        try await service.removeSharedItem(id: "shared-project-1", scope: .project)
        let projects = try await service.fetchSharedProjects()

        #expect(projects.contains { $0.id == "shared-project-1" })
    }

    @Test func fetchSharedProjects_stopsWhenAnEmptyPageClaimsMorePages() async throws {
        let requestedPages = RequestedPages()
        let client = SharedHTTPClient { endpoint in
            guard endpoint.path == "/api/v1/shared-projects" else {
                Issue.record("Unexpected endpoint: \(endpoint.path)")
                return .failure(.networkError)
            }

            let page = Int(endpoint.queryItems.first { $0.name == "page" }?.value ?? "")
            await requestedPages.append(page)

            switch page {
            case 1:
                return .success(Self.sharedProjectsFirstPageJSON)
            case 2:
                return .success(Self.emptySharedProjectsPageJSON)
            default:
                Issue.record("Unexpected page: \(String(describing: page))")
                return .failure(.networkError)
            }
        }
        let service = RemoteSharedService(httpClient: client, now: { Self.fixtureNow })

        let projects = try await service.fetchSharedProjects()
        let pages = await requestedPages.values

        #expect(projects.map(\.id) == ["shared-project-1"])
        #expect(pages == [1, 2])
    }

    @Test func fetchSharedItems_excludesInactiveItemsPastTheRetentionPeriod() async throws {
        let client = SharedHTTPClient { endpoint in
            switch endpoint.path {
            case "/api/v1/shared-projects":
                return .success(Self.sharedProjectsWithExpiredInactiveItemsJSON)
            case "/api/v1/shared-scans":
                return .success(Self.sharedScansWithExpiredInactiveItemsJSON)
            default:
                Issue.record("Unexpected endpoint: \(endpoint.path)")
                return .failure(.networkError)
            }
        }
        let service = RemoteSharedService(httpClient: client, now: { Self.fixtureNow })

        let projects = try await service.fetchSharedProjects()
        let scans = try await service.fetchSharedScans()

        #expect(projects.map(\.id) == ["shared-project-1"])
        #expect(scans.map(\.id) == ["shared-scan-1"])
    }

    @Test func fetchSharedScans_remoteRevocationOverridesNewerLocallyIngestedItem() async throws {
        let client = SharedHTTPClient { endpoint in
            switch endpoint.path {
            case "/api/v1/shared-projects":
                return .success(Self.sharedProjectsJSON)
            case "/api/v1/shared-scans":
                return .success(Self.sharedScansJSON)
            default:
                Issue.record("Unexpected endpoint: \(endpoint.path)")
                return .failure(.networkError)
            }
        }
        let service = RemoteSharedService(httpClient: client, now: { Self.fixtureNow })
        let locallyAcceptedScan = SharedScanItem(
            id: "shared-scan-revoked",
            name: "Revoked Scan",
            ownerName: "Owner",
            noteCount: 0,
            projectID: "shared-project-revoked",
            projectName: "Revoked Project",
            thumbnailName: nil,
            status: .active,
            statusChangedAt: Self.fixtureNow,
            detailScan: nil
        )
        try await service.ingestSharedScan(locallyAcceptedScan)

        let scans = try await service.fetchSharedScans()

        #expect(scans.first { $0.id == locallyAcceptedScan.id }?.status == .accessRevoked)
    }

    @Test func fetchSharedProjects_prefersRemoteDetailOverNewerLocalStub() async throws {
        let client = SharedHTTPClient { endpoint in
            switch endpoint.path {
            case "/api/v1/shared-projects":
                return .success(Self.sharedProjectsJSON)
            default:
                Issue.record("Unexpected endpoint: \(endpoint.path)")
                return .failure(.networkError)
            }
        }
        let service = RemoteSharedService(httpClient: client, now: { Self.fixtureNow })
        let localStub = SharedProjectItem(
            id: "shared-project-1",
            name: "",
            ownerName: "",
            scanCount: 0,
            thumbnailName: nil,
            status: .active,
            statusChangedAt: Self.fixtureNow.addingTimeInterval(3_600),
            detailProject: nil
        )
        try await service.ingestSharedProject(localStub)

        let projects = try await service.fetchSharedProjects()
        let item = projects.first { $0.id == "shared-project-1" }

        #expect(item?.name == "Shared Project")
        #expect(item?.detailProject != nil)
    }

    @Test func fetchSharedItems_dropsInactiveLocalStubsMissingFromAPI() async throws {
        let client = SharedHTTPClient { endpoint in
            switch endpoint.path {
            case "/api/v1/shared-projects", "/api/v1/shared-scans":
                return .success(Self.emptySharedProjectsPageJSON)
            default:
                Issue.record("Unexpected endpoint: \(endpoint.path)")
                return .failure(.networkError)
            }
        }
        let service = RemoteSharedService(httpClient: client, now: { Self.fixtureNow })

        try await service.ingestSharedProject(
            SharedProjectItem(
                id: "locally-revoked-project",
                name: "Revoked Project",
                ownerName: "Owner",
                scanCount: 0,
                thumbnailName: nil,
                status: .accessRevoked,
                statusChangedAt: Self.fixtureNow,
                detailProject: nil
            )
        )
        try await service.ingestSharedScan(
            SharedScanItem(
                id: "locally-deleted-scan",
                name: "Deleted Scan",
                ownerName: "Owner",
                noteCount: 0,
                projectID: "project-id",
                projectName: "Project",
                thumbnailName: nil,
                status: .itemDeleted,
                statusChangedAt: Self.fixtureNow,
                detailScan: nil
            )
        )

        let projects = try await service.fetchSharedProjects()
        let scans = try await service.fetchSharedScans()

        #expect(projects.isEmpty)
        #expect(scans.isEmpty)
    }

    private static let fixtureNow = Date(timeIntervalSince1970: 1_786_768_170)

    private static let sharedProjectsJSON = Data(
        """
        {
          "items": [{
            "id": "shared-project-1",
            "name": "Shared Project",
            "owner": { "id": "owner-1", "email": "owner@example.com", "displayName": "Project Owner" },
            "scanCount": 1,
            "thumbnail": null,
            "updatedAt": "2026-08-13T04:29:30.089Z",
            "status": "ACTIVE",
            "permissions": { "canView": true }
          }, {
            "id": "shared-project-revoked",
            "name": "Revoked Project",
            "owner": { "id": "owner-1", "email": "owner@example.com" },
            "scanCount": 1,
            "thumbnail": null,
            "updatedAt": "2026-08-12T04:29:30.089Z",
            "status": "REVOKED",
            "permissions": { "canView": false }
          }, {
            "id": "shared-project-deleted",
            "name": "Deleted Project",
            "owner": { "id": "owner-1", "email": null, "displayName": null },
            "scanCount": 0,
            "thumbnail": null,
            "updatedAt": "2026-08-11T04:29:30.089Z",
            "status": "DELETED",
            "permissions": { "canView": false }
          }],
          "pagination": { "page": 1, "limit": 50, "total": 3, "totalPages": 1 }
        }
        """.utf8
    )

    private static let sharedProjectsFirstPageJSON = Data(
        """
        {
          "items": [{
            "id": "shared-project-1",
            "name": "Shared Project",
            "owner": { "id": "owner-1", "email": "owner@example.com" },
            "scanCount": 1,
            "thumbnail": null,
            "updatedAt": "2026-08-13T04:29:30.089Z",
            "status": "ACTIVE",
            "permissions": { "canView": true }
          }],
          "pagination": { "page": 1, "limit": 50, "total": 1, "totalPages": 2 }
        }
        """.utf8
    )

    private static let sharedProjectsWithExpiredInactiveItemsJSON = Data(
        String(decoding: sharedProjectsJSON, as: UTF8.self)
            .replacingOccurrences(of: "2026-08-12T04:29:30.089Z", with: "2026-08-07T04:29:30.089Z")
            .replacingOccurrences(of: "2026-08-11T04:29:30.089Z", with: "2026-08-07T04:29:30.089Z")
            .utf8
    )

    private static let emptySharedProjectsPageJSON = Data(
        """
        {
          "items": [],
          "pagination": { "page": 1, "limit": 50, "total": 1, "totalPages": 2 }
        }
        """.utf8
    )

    private static let sharedScansJSON = Data(
        """
        {
          "items": [{
            "id": "shared-scan-1",
            "projectId": "shared-project-1",
            "name": "Shared Scan",
            "thumbnail": "https://example.com/thumbnail",
            "creator": { "id": "owner-1", "email": "owner@example.com", "displayName": "Scan Creator" },
            "noteCount": 2,
            "syncStatus": "SYNCED",
            "updatedAt": "2026-08-13T04:29:30.089Z",
            "status": "ACTIVE",
            "permissions": { "canView": true }
          }, {
            "id": "shared-scan-revoked",
            "projectId": "shared-project-revoked",
            "name": "Revoked Scan",
            "thumbnail": null,
            "creator": { "id": "owner-1", "email": "owner@example.com" },
            "noteCount": 0,
            "syncStatus": "SYNCED",
            "updatedAt": "2026-08-12T04:29:30.089Z",
            "status": "REVOKED",
            "permissions": { "canView": false }
          }],
          "pagination": { "page": 1, "limit": 50, "total": 2, "totalPages": 1 }
        }
        """.utf8
    )

    private static let sharedScansWithExpiredInactiveItemsJSON = Data(
        String(decoding: sharedScansJSON, as: UTF8.self)
            .replacingOccurrences(of: "2026-08-12T04:29:30.089Z", with: "2026-08-07T04:29:30.089Z")
            .utf8
    )
}

private actor RequestedPages {
    private(set) var values: [Int?] = []

    func append(_ page: Int?) {
        values.append(page)
    }
}

private struct SharedHTTPClient: HTTPClient {
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
