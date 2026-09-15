//
//  RemoteInvitationServiceTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

struct RemoteInvitationServiceTests {
    @Test func fetchInvitation_getsPreviewPathAndMapsProject() async throws {
        let token = "uRly-Hf-plhnjPHkgJ-t9btOXwYTcA9XnH76tDcQRwk"
        let recorder = InvitationHTTPRecorder()
        let client = FakeInvitationHTTPClient { endpoint in
            await recorder.record(endpoint)
            #expect(endpoint.path == "/api/v1/invitations/\(token)")
            #expect(endpoint.method == .get)
            return .success(Self.previewJSON())
        }
        let service = RemoteInvitationService(httpClient: client)

        let details = try await service.fetchInvitation(
            scope: .project,
            token: token,
            currentUserEmail: "viewer@example.com"
        )

        #expect(details.token == token)
        #expect(details.scope == .project)
        #expect(details.type == .shareLink)
        #expect(details.title == "Lakeside Remodel")
        #expect(details.invitedEmail == "viewer@example.com")
        #expect(details.existingAccessDestination != nil)
        #expect(details.showsThumbnail)
        #expect(details.project?.id == "3fa85f64-5717-4562-b3fc-2c963f66afa6")
        #expect(details.scan == nil)
        #expect(await recorder.requests.count == 1)
    }

    @Test func fetchInvitation_mapsScanPreview() async throws {
        let client = FakeInvitationHTTPClient { _ in .success(Self.scanPreviewJSON()) }
        let service = RemoteInvitationService(httpClient: client)

        let details = try await service.fetchInvitation(
            scope: .scan,
            token: "scan-token",
            currentUserEmail: nil
        )

        #expect(details.scope == .scan)
        #expect(details.type == .shareLink)
        #expect(details.title == "A")
        #expect(details.ownerName == "owner@example.com")
        #expect(details.itemCount == 1)
        #expect(details.existingAccessDestination != nil)
        #expect(details.project == nil)
        #expect(details.scan?.id == "151437be-a08f-4be6-a9e9-b60464f2e3af")
    }

    @Test func fetchInvitation_mapsAcceptedStatus() async {
        let client = FakeInvitationHTTPClient { _ in
            .success(Self.previewJSON(status: "ACCEPTED"))
        }
        let service = RemoteInvitationService(httpClient: client)

        await #expect(throws: InvitationServiceError.alreadyAccepted) {
            try await service.fetchInvitation(
                scope: .project,
                token: "accepted-token",
                currentUserEmail: nil
            )
        }
    }

    @Test func fetchInvitation_mapsDeclinedStatus() async {
        let client = FakeInvitationHTTPClient { _ in
            .success(Self.previewJSON(status: "DECLINED"))
        }
        let service = RemoteInvitationService(httpClient: client)

        await #expect(throws: InvitationServiceError.declined) {
            try await service.fetchInvitation(
                scope: .project,
                token: "declined-token",
                currentUserEmail: nil
            )
        }
    }

    @Test func fetchInvitation_mapsRevokedStatus() async {
        let client = FakeInvitationHTTPClient { _ in
            .success(Self.previewJSON(status: "REVOKED"))
        }
        let service = RemoteInvitationService(httpClient: client)

        await #expect(throws: InvitationServiceError.unavailable) {
            try await service.fetchInvitation(
                scope: .project,
                token: "revoked-token",
                currentUserEmail: nil
            )
        }
    }

    @Test func fetchInvitation_mapsExpiredStatus() async {
        let client = FakeInvitationHTTPClient { _ in
            .success(Self.previewJSON(status: "EXPIRED"))
        }
        let service = RemoteInvitationService(httpClient: client)

        await #expect(throws: InvitationServiceError.expired) {
            try await service.fetchInvitation(
                scope: .project,
                token: "expired-token",
                currentUserEmail: nil
            )
        }
    }

    @Test func fetchInvitation_mapsPastExpiryDate() async {
        let client = FakeInvitationHTTPClient { _ in
            .success(Self.previewJSON(expiresAt: "2020-01-01T00:00:00.000Z"))
        }
        let service = RemoteInvitationService(httpClient: client)

        await #expect(throws: InvitationServiceError.expired) {
            try await service.fetchInvitation(
                scope: .project,
                token: "stale-token",
                currentUserEmail: nil
            )
        }
    }

    @Test func fetchInvitation_rejectsPreviewIssuedToAnotherEmail() async {
        let client = FakeInvitationHTTPClient { _ in
            .success(Self.previewJSON(recipientEmail: "viewer@example.com", hasAccess: true))
        }
        let service = RemoteInvitationService(httpClient: client)

        await #expect(throws: InvitationServiceError.accessDenied) {
            try await service.fetchInvitation(
                scope: .project,
                token: "other-users-token",
                currentUserEmail: "different-user@example.com"
            )
        }
    }

    @Test func fetchInvitation_allowsRecipientWithoutExistingAccess() async throws {
        let client = FakeInvitationHTTPClient { _ in
            .success(Self.previewJSON(recipientEmail: "viewer@example.com", hasAccess: false))
        }
        let service = RemoteInvitationService(httpClient: client)

        let details = try await service.fetchInvitation(
            scope: .project,
            token: "recipient-token",
            currentUserEmail: "viewer@example.com"
        )

        #expect(details.invitedEmail == "viewer@example.com")
        #expect(details.existingAccessDestination == nil)
    }

    @Test func fetchInvitation_mapsInvitationType() async throws {
        let client = FakeInvitationHTTPClient { _ in
            .success(Self.previewJSON(type: "invitation", hasAccess: false))
        }
        let service = RemoteInvitationService(httpClient: client)

        let details = try await service.fetchInvitation(
            scope: .project,
            token: "invitation-token",
            currentUserEmail: "viewer@example.com"
        )

        #expect(details.type == .invitation)
    }

    @Test func fetchInvitation_mapsShareLinkTypeWithUnderscore() async throws {
        let client = FakeInvitationHTTPClient { _ in
            .success(Self.previewJSON(type: "SHARE_LINK", hasAccess: true))
        }
        let service = RemoteInvitationService(httpClient: client)

        let details = try await service.fetchInvitation(
            scope: .project,
            token: "share-link-underscore-token",
            currentUserEmail: "viewer@example.com"
        )

        #expect(details.type == .shareLink)
    }

    @Test func fetchInvitation_defaultsUnknownLinkTypeToInvitation() async throws {
        let client = FakeInvitationHTTPClient { _ in
            .success(Self.previewJSON(type: "unknown-type", hasAccess: false))
        }
        let service = RemoteInvitationService(httpClient: client)

        let details = try await service.fetchInvitation(
            scope: .project,
            token: "unknown-type-token",
            currentUserEmail: "viewer@example.com"
        )

        #expect(details.type == .invitation)
    }

    @Test func fetchInvitation_maps404ToNotFound() async {
        let client = FakeInvitationHTTPClient { _ in
            .failure(.serverError(statusCode: 404, apiError: nil))
        }
        let service = RemoteInvitationService(httpClient: client)

        await #expect(throws: InvitationServiceError.notFound) {
            try await service.fetchInvitation(
                scope: .project,
                token: "missing-token",
                currentUserEmail: nil
            )
        }
    }

    @Test func fetchInvitation_mapsNetworkError() async {
        let client = FakeInvitationHTTPClient { _ in .failure(.networkError) }
        let service = RemoteInvitationService(httpClient: client)

        await #expect(throws: InvitationServiceError.network) {
            try await service.fetchInvitation(
                scope: .project,
                token: "token",
                currentUserEmail: nil
            )
        }
    }

    @Test func fetchInvitation_rejectsPathSeparatorsAndDotSegmentsInToken() async {
        let client = FakeInvitationHTTPClient { endpoint in
            Issue.record("Unexpected endpoint: \(endpoint.path)")
            return .failure(.networkError)
        }
        let service = RemoteInvitationService(httpClient: client)

        for token in ["token/extra", "../projects", "%2E%2E%2Fprojects"] {
            await #expect(throws: InvitationServiceError.unavailable) {
                try await service.fetchInvitation(scope: .project, token: token, currentUserEmail: nil)
            }
        }
    }

    @Test func acceptInvitation_postsAcceptPathAndMapsProject() async throws {
        let token = "invite-token"
        let recorder = InvitationHTTPRecorder()
        let client = FakeInvitationHTTPClient { endpoint in
            await recorder.record(endpoint)
            #expect(endpoint.path == "/api/v1/invitations/\(token)/accept")
            #expect(endpoint.method == .post)
            return .success(Self.acceptJSON())
        }
        let service = RemoteInvitationService(httpClient: client)

        let destination = try await service.acceptInvitation(
            scope: .project,
            token: token,
            currentUserEmail: "viewer@example.com"
        )

        guard case .project(let project) = destination else {
            Issue.record("Expected project destination")
            return
        }
        #expect(project.id == "3fa85f64-5717-4562-b3fc-2c963f66afa6")
        #expect(project.name == "Lakeside Remodel")
        #expect(project.ownerName == "owner@example.com")
        #expect(await recorder.requests.count == 1)
    }

    @Test func acceptInvitation_mapsScanShareLinkResponse() async throws {
        let client = FakeInvitationHTTPClient { _ in .success(Self.acceptScanJSON()) }
        let service = RemoteInvitationService(httpClient: client)

        let destination = try await service.acceptInvitation(
            scope: .scan,
            token: "scan-token",
            currentUserEmail: nil
        )

        guard case .scan(let scan) = destination else {
            Issue.record("Expected scan destination")
            return
        }
        #expect(scan.id == "151437be-a08f-4be6-a9e9-b60464f2e3af")
        #expect(scan.name == "A")
        #expect(scan.noteCount == 1)
        #expect(scan.projectName == "H3")
        #expect(scan.status == .active)
    }

    @Test func declineInvitation_postsDeclinePath() async throws {
        let token = "invite-token"
        let recorder = InvitationHTTPRecorder()
        let client = FakeInvitationHTTPClient { endpoint in
            await recorder.record(endpoint)
            #expect(endpoint.path == "/api/v1/invitations/\(token)/decline")
            #expect(endpoint.method == .post)
            return .success(Self.declineJSON())
        }
        let service = RemoteInvitationService(httpClient: client)

        try await service.declineInvitation(
            scope: .project,
            token: token,
            currentUserEmail: "viewer@example.com"
        )

        #expect(await recorder.requests.count == 1)
    }

    @Test func acceptInvitation_maps403ToAccessDenied() async {
        let client = FakeInvitationHTTPClient { _ in
            .failure(.serverError(statusCode: 403, apiError: nil))
        }
        let service = RemoteInvitationService(httpClient: client)

        await #expect(throws: InvitationServiceError.accessDenied) {
            try await service.acceptInvitation(
                scope: .project,
                token: "token",
                currentUserEmail: nil
            )
        }
    }

    @Test func declineInvitation_mapsNetworkError() async {
        let client = FakeInvitationHTTPClient { _ in .failure(.networkError) }
        let service = RemoteInvitationService(httpClient: client)

        await #expect(throws: InvitationServiceError.network) {
            try await service.declineInvitation(
                scope: .project,
                token: "token",
                currentUserEmail: nil
            )
        }
    }

    private static func acceptJSON() -> Data {
        return Data(
            """
            {
              "type": "share-link",
              "shareLinkId": "2319ec00-5f84-49f6-8a4d-59a7e7093f88",
              "scope": "project",
              "project": {
                "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
                "name": "Lakeside Remodel",
                "description": "Shared living spaces",
                "thumbnail": "https://example.com/thumb.jpg",
                "owner": {
                  "id": "owner-user-1",
                  "email": "owner@example.com"
                }
              },
              "scan": null,
              "access": {
                "role": "VIEWER",
                "status": "ACTIVE",
                "grantedAt": "2026-08-17T07:16:49.031Z"
              }
            }
            """.utf8
        )
    }

    private static func declineJSON() -> Data {
        return Data(
            """
            {
              "invitationId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
              "status": "DECLINED",
              "declinedAt": "2026-08-17T07:17:50.839Z"
            }
            """.utf8
        )
    }

    private static func acceptScanJSON() -> Data {
        return Data(
            """
            {
              "type": "invitation",
              "scope": "scan",
              "project": null,
              "scan": {
                "id": "151437be-a08f-4be6-a9e9-b60464f2e3af",
                "projectId": "df20f6dc-7443-4465-a58d-cfc67fd720fd",
                "projectName": "H3",
                "name": "A",
                "description": null,
                "thumbnail": "https://example.com/thumbnail.jpg",
                "noteCount": 1,
                "creator": {
                  "id": "owner-user-1",
                  "email": "owner@example.com"
                }
              },
              "status": "PENDING",
              "recipientEmail": "viewer@example.com",
              "sentAt": "2026-08-24T07:38:29.996Z",
              "expiresAt": "2026-08-31T07:38:29.996Z",
              "hasAccess": false
            }
            """.utf8
        )
    }

    private static func previewJSON(
        type: String = "share-link",
        status: String = "ACTIVE",
        expiresAt: String = "2027-08-17T04:53:54.132Z",
        recipientEmail: String? = "viewer@example.com",
        hasAccess: Bool? = true
    ) -> Data {
        let recipientEmailJSON = recipientEmail.map { "\"\($0)\"" } ?? "null"
        let hasAccessJSON = hasAccess.map(String.init) ?? "null"

        return Data(
            """
            {
              "type": "\(type)",
              "scope": "project",
              "project": {
                "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
                "name": "Lakeside Remodel",
                "description": "Shared living spaces",
                "thumbnail": "https://example.com/thumb.jpg",
                "owner": {
                  "id": "owner-user-1",
                  "email": "owner@example.com"
                },
                "scanCount": 2
              },
              "scan": null,
              "status": "\(status)",
              "recipientEmail": \(recipientEmailJSON),
              "expiresAt": "\(expiresAt)",
              "hasAccess": \(hasAccessJSON)
            }
            """.utf8
        )
    }

    private static func scanPreviewJSON() -> Data {
        let expiresAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86_400))

        return Data(
            """
            {
              "type": "share-link",
              "scope": "scan",
              "project": null,
              "scan": {
                "id": "151437be-a08f-4be6-a9e9-b60464f2e3af",
                "projectId": "df20f6dc-7443-4465-a58d-cfc67fd720fd",
                "name": "A",
                "description": null,
                "thumbnail": "https://example.com/thumbnail.jpg",
                "noteCount": 1,
                "creator": {
                  "id": "owner-user-1",
                  "email": "owner@example.com"
                }
              },
              "status": "ACTIVE",
              "expiresAt": "\(expiresAt)",
              "hasAccess": true
            }
            """.utf8
        )
    }
}

private actor InvitationHTTPRecorder {
    private(set) var requests: [APIEndpoint] = []

    func record(_ endpoint: APIEndpoint) {
        requests.append(endpoint)
    }
}

private struct FakeInvitationHTTPClient: HTTPClient {
    enum Outcome: Sendable {
        case success(Data)
        case failure(HTTPClientError)
    }

    private let handler: @Sendable (APIEndpoint) async throws -> Outcome

    init(handler: @escaping @Sendable (APIEndpoint) async throws -> Outcome) {
        self.handler = handler
    }

    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        switch try await handler(endpoint) {
        case .success(let data):
            return try LiveHTTPClient.makeAPIDecoder().decode(T.self, from: data)
        case .failure(let error):
            throw error
        }
    }
}
