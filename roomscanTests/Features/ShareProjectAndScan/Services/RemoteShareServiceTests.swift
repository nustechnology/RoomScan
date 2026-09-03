//
//  RemoteShareServiceTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

struct RemoteShareServiceTests {
    @Test func sendInvitation_postsProjectPathAndMapsResponse() async throws {
        let recorder = ShareHTTPRecorder()
        let client = FakeShareHTTPClient { endpoint in
            await recorder.record(endpoint)
            #expect(endpoint.path == "/api/v1/projects/project-1/invitations")
            #expect(endpoint.method == .post)
            #expect(UUID(uuidString: endpoint.headers["Idempotency-Key"] ?? "") != nil)
            let object = try JSONSerialization.jsonObject(with: endpoint.body ?? Data()) as? [String: Any]
            #expect(object?["recipientEmail"] as? String == "user@example.com")
            #expect((object?["expiresInSeconds"] as? NSNumber)?.intValue == 60)
            return .success(Self.invitationJSON())
        }
        let service = RemoteShareService(httpClient: client, invitationLifetimeSeconds: 60)
        let input = ShareScreenInput.project(id: "project-1", name: "Lakeside Remodel")

        let member = try await service.sendInvitation(for: input, email: "user@example.com")

        #expect(member.id == "3fa85f64-5717-4562-b3fc-2c963f66afa6")
        #expect(member.email == "user@example.com")
        #expect(member.status == .pending)
        #expect(await recorder.requests.count == 1)
    }

    @Test func loadInvitedMembers_mapsPendingInvitationsAndViewers() async throws {
        let recorder = ShareHTTPRecorder()
        let client = FakeShareHTTPClient { endpoint in
            await recorder.record(endpoint)
            #expect(endpoint.path == "/api/v1/projects/project-1/shares")
            #expect(endpoint.method == .get)
            return .success(Self.sharesJSON())
        }
        let service = RemoteShareService(httpClient: client)
        let input = ShareScreenInput.project(id: "project-1", name: "Lakeside Remodel")

        let snapshot = try await service.loadInvitedMembers(for: input)

        #expect(snapshot.members.count == 2)
        #expect(snapshot.members[0].id == "3fa85f64-5717-4562-b3fc-2c963f66afa6")
        #expect(snapshot.members[0].email == "pending@example.com")
        #expect(snapshot.members[0].status == .pending)
        #expect(snapshot.members[1].id == "viewer-user-1")
        #expect(snapshot.members[1].email == "viewer@example.com")
        #expect(snapshot.members[1].status == .accepted)
        #expect(snapshot.members[1].acceptedAt != nil)
        #expect(await recorder.requests.count == 1)
    }

    @Test func loadInvitedMembers_scanUsesScanID() async throws {
        let recorder = ShareHTTPRecorder()
        let client = FakeShareHTTPClient { endpoint in
            await recorder.record(endpoint)
            return .success(Self.sharesJSON())
        }
        let service = RemoteShareService(httpClient: client)
        let input = ShareScreenInput.scan(
            projectID: nil,
            projectName: nil,
            scanID: "scan-1",
            scanName: "Living Room",
            syncStatus: .synced
        )

        _ = try await service.loadInvitedMembers(for: input)

        #expect(await recorder.requests.first?.path == "/api/v1/scans/scan-1/shares")
    }

    @Test func loadInvitedMembers_mapsNetworkErrorToOffline() async {
        let client = FakeShareHTTPClient { _ in .failure(.networkError) }
        let service = RemoteShareService(httpClient: client)
        let input = ShareScreenInput.project(id: "project-1", name: "Project")

        await #expect(throws: ShareServiceError.offline) {
            try await service.loadInvitedMembers(for: input)
        }
    }

    @Test func sendInvitation_scanUsesScanID() async throws {
        let recorder = ShareHTTPRecorder()
        let client = FakeShareHTTPClient { endpoint in
            await recorder.record(endpoint)
            return .success(Self.invitationJSON())
        }
        let service = RemoteShareService(httpClient: client, invitationLifetimeSeconds: 60)
        let input = ShareScreenInput.scan(
            projectID: "project-1",
            projectName: "Lakeside Remodel",
            scanID: "scan-1",
            scanName: "Living Room",
            syncStatus: .synced
        )

        _ = try await service.sendInvitation(for: input, email: "user@example.com")

        let requests = await recorder.requests
        #expect(requests.first?.path == "/api/v1/scans/scan-1/invitations")
    }

    @Test func copyInvitationLink_scanCreatesShareLinkAndReturnsServerURL() async throws {
        let recorder = ShareHTTPRecorder()
        let client = FakeShareHTTPClient { endpoint in
            await recorder.record(endpoint)
            #expect(endpoint.path == "/api/v1/scans/scan-1/share-links")
            #expect(endpoint.method == .post)
            #expect(UUID(uuidString: endpoint.headers["Idempotency-Key"] ?? "") != nil)
            return .success(Self.scanShareLinkJSON())
        }
        let service = RemoteShareService(httpClient: client)
        let input = ShareScreenInput.scan(
            projectID: nil,
            projectName: nil,
            scanID: "scan-1",
            scanName: "Living Room",
            syncStatus: .synced
        )

        let url = try await service.copyInvitationLink(for: input)

        #expect(url.absoluteString == "https://roomscan.nustechnology.com/invitations/Ty0opzDc7Uv6IzWCJbSQfz8zVE1xM0TZy74T-RHsa-E?scope=scan")
        #expect(await recorder.requests.count == 1)
    }

    @Test func copyInvitationLink_projectCreatesShareLinkAndReturnsServerURL() async throws {
        let recorder = ShareHTTPRecorder()
        let client = FakeShareHTTPClient { endpoint in
            await recorder.record(endpoint)
            #expect(endpoint.path == "/api/v1/projects/project-1/share-links")
            #expect(endpoint.method == .post)
            #expect(UUID(uuidString: endpoint.headers["Idempotency-Key"] ?? "") != nil)
            return .success(Self.projectShareLinkJSON())
        }
        let service = RemoteShareService(httpClient: client)
        let input = ShareScreenInput.project(id: "project-1", name: "Lakeside Remodel")

        let url = try await service.copyInvitationLink(for: input)

        #expect(url.absoluteString == "https://roomscan.nustechnology.com/invitations/project-token?scope=project")
        #expect(await recorder.requests.count == 1)
    }

    @Test func sendInvitation_mapsDuplicateServerError() async {
        let client = FakeShareHTTPClient { _ in
            .failure(
                .serverError(
                    statusCode: 400,
                    apiError: APIErrorResponse(
                        error: APIErrorBody(
                            code: "DUPLICATE_INVITATION",
                            message: "Already invited",
                            details: nil
                        ),
                        requestId: "req-1"
                    )
                )
            )
        }
        let service = RemoteShareService(httpClient: client)
        let input = ShareScreenInput.project(id: "project-1", name: "Project")

        await #expect(throws: ShareServiceError.duplicateEmail) {
            try await service.sendInvitation(for: input, email: "user@example.com")
        }
    }

    @Test func sendInvitation_mapsNetworkErrorToOffline() async {
        let client = FakeShareHTTPClient { _ in .failure(.networkError) }
        let service = RemoteShareService(httpClient: client)
        let input = ShareScreenInput.project(id: "project-1", name: "Project")

        await #expect(throws: ShareServiceError.offline) {
            try await service.sendInvitation(for: input, email: "user@example.com")
        }
    }

    @Test func revokeInvitation_deletesInvitationPathAndClearsCache() async throws {
        let invitationID = "3fa85f64-5717-4562-b3fc-2c963f66afa6"
        let recorder = ShareHTTPRecorder()
        let client = FakeShareHTTPClient { endpoint in
            await recorder.record(endpoint)
            if endpoint.method == .get {
                return .success(Self.sharesJSON())
            }
            #expect(endpoint.path == "/api/v1/invitations/\(invitationID)")
            #expect(endpoint.method == .delete)
            return .success(Self.revokeInvitationJSON(invitationID: invitationID))
        }
        let service = RemoteShareService(httpClient: client)
        let input = ShareScreenInput.project(id: "project-1", name: "Lakeside Remodel")

        _ = try await service.loadInvitedMembers(for: input)
        try await service.revokeInvitation(for: input, id: invitationID)

        let requests = await recorder.requests
        #expect(requests.count == 2)
        #expect(requests.last?.method == .delete)
        #expect(requests.last?.path == "/api/v1/invitations/\(invitationID)")
    }

    @Test func revokeInvitation_maps404ToMemberNotFound() async {
        let client = FakeShareHTTPClient { _ in
            .failure(.serverError(statusCode: 404, apiError: nil))
        }
        let service = RemoteShareService(httpClient: client)
        let input = ShareScreenInput.project(id: "project-1", name: "Project")

        await #expect(throws: ShareServiceError.memberNotFound) {
            try await service.revokeInvitation(for: input, id: "missing-id")
        }
    }

    @Test func revokeInvitation_mapsNetworkErrorToOffline() async {
        let client = FakeShareHTTPClient { _ in .failure(.networkError) }
        let service = RemoteShareService(httpClient: client)
        let input = ShareScreenInput.project(id: "project-1", name: "Project")

        await #expect(throws: ShareServiceError.offline) {
            try await service.revokeInvitation(for: input, id: "invitation-1")
        }
    }

    @Test func resendInvitation_postsResendPathAndMapsResponse() async throws {
        let invitationID = "3fa85f64-5717-4562-b3fc-2c963f66afa6"
        let recorder = ShareHTTPRecorder()
        let client = FakeShareHTTPClient { endpoint in
            await recorder.record(endpoint)
            if endpoint.method == .get {
                return .success(Self.sharesJSON())
            }
            #expect(endpoint.path == "/api/v1/invitations/\(invitationID)/resend")
            #expect(endpoint.method == .post)
            return .success(Self.resendInvitationJSON(invitationID: invitationID))
        }
        let service = RemoteShareService(httpClient: client)
        let input = ShareScreenInput.project(id: "project-1", name: "Lakeside Remodel")

        _ = try await service.loadInvitedMembers(for: input)
        let member = try await service.resendInvitation(for: input, id: invitationID)

        #expect(member.id == invitationID)
        #expect(member.email == "pending@example.com")
        #expect(member.status == .pending)
        let requests = await recorder.requests
        #expect(requests.count == 2)
        #expect(requests.last?.method == .post)
        #expect(requests.last?.path == "/api/v1/invitations/\(invitationID)/resend")
    }

    @Test func resendInvitation_maps404ToMemberNotFound() async {
        let client = FakeShareHTTPClient { _ in
            .failure(.serverError(statusCode: 404, apiError: nil))
        }
        let service = RemoteShareService(httpClient: client)
        let input = ShareScreenInput.project(id: "project-1", name: "Project")

        await #expect(throws: ShareServiceError.memberNotFound) {
            try await service.resendInvitation(for: input, id: "missing-id")
        }
    }

    @Test func resendInvitation_mapsNetworkErrorToOffline() async {
        let client = FakeShareHTTPClient { _ in .failure(.networkError) }
        let service = RemoteShareService(httpClient: client)
        let input = ShareScreenInput.project(id: "project-1", name: "Project")

        await #expect(throws: ShareServiceError.offline) {
            try await service.resendInvitation(for: input, id: "invitation-1")
        }
    }

    @Test func revokeAccess_deletesSharePathAndClearsCache() async throws {
        let userID = "viewer-user-1"
        let recorder = ShareHTTPRecorder()
        let client = FakeShareHTTPClient { endpoint in
            await recorder.record(endpoint)
            if endpoint.method == .get {
                return .success(Self.sharesJSON())
            }
            #expect(endpoint.path == "/api/v1/projects/project-1/shares/\(userID)")
            #expect(endpoint.method == .delete)
            return .success(Self.revokeAccessJSON(projectID: "project-1", userID: userID))
        }
        let service = RemoteShareService(httpClient: client)
        let input = ShareScreenInput.project(id: "project-1", name: "Lakeside Remodel")

        _ = try await service.loadInvitedMembers(for: input)
        try await service.revokeAccess(for: input, userID: userID)

        let requests = await recorder.requests
        #expect(requests.count == 2)
        #expect(requests.last?.method == .delete)
        #expect(requests.last?.path == "/api/v1/projects/project-1/shares/\(userID)")
    }

    @Test func revokeAccess_scanUsesScanID() async throws {
        let userID = "viewer-user-1"
        let recorder = ShareHTTPRecorder()
        let client = FakeShareHTTPClient { endpoint in
            await recorder.record(endpoint)
            if endpoint.method == .get {
                return .success(Self.sharesJSON())
            }
            return .success(Self.revokeScanAccessJSON(scanID: "scan-1", userID: userID))
        }
        let service = RemoteShareService(httpClient: client)
        let input = ShareScreenInput.scan(
            projectID: "project-1",
            projectName: "Lakeside Remodel",
            scanID: "scan-1",
            scanName: "Living Room",
            syncStatus: .synced
        )

        _ = try await service.loadInvitedMembers(for: input)
        try await service.revokeAccess(for: input, userID: userID)

        #expect(await recorder.requests.last?.path == "/api/v1/scans/scan-1/shares/\(userID)")
    }

    @Test func revokeAccess_maps404ToMemberNotFound() async {
        let client = FakeShareHTTPClient { _ in
            .failure(.serverError(statusCode: 404, apiError: nil))
        }
        let service = RemoteShareService(httpClient: client)
        let input = ShareScreenInput.project(id: "project-1", name: "Project")

        await #expect(throws: ShareServiceError.memberNotFound) {
            try await service.revokeAccess(for: input, userID: "missing-user")
        }
    }

    @Test func revokeAccess_mapsNetworkErrorToOffline() async {
        let client = FakeShareHTTPClient { _ in .failure(.networkError) }
        let service = RemoteShareService(httpClient: client)
        let input = ShareScreenInput.project(id: "project-1", name: "Project")

        await #expect(throws: ShareServiceError.offline) {
            try await service.revokeAccess(for: input, userID: "viewer-user-1")
        }
    }

    private static func invitationJSON() -> Data {
        Data(
            """
            {
              "invitationId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
              "invitationUrl": "https://example.com/",
              "recipientEmail": "user@example.com",
              "expiresAt": "2026-08-14T09:23:11.425Z",
              "status": "PENDING",
              "sentAt": "2026-08-14T09:23:11.425Z"
            }
            """.utf8
        )
    }

    private static func scanShareLinkJSON() -> Data {
        Data(
            """
            {
              "shareLinkId": "9f2dfb07-47ec-44ce-bc7d-4e7a5a3b2f0c",
              "shareLinkUrl": "https://roomscan.nustechnology.com/invitations/Ty0opzDc7Uv6IzWCJbSQfz8zVE1xM0TZy74T-RHsa-E?scope=scan",
              "scope": "scan",
              "expiresAt": "2026-08-28T09:54:15.644Z"
            }
            """.utf8
        )
    }

    private static func projectShareLinkJSON() -> Data {
        Data(
            """
            {
              "shareLinkId": "a7f9f964-4324-40ba-ac8d-8d0a7d53480a",
              "shareLinkUrl": "https://roomscan.nustechnology.com/invitations/project-token?scope=project",
              "scope": "project",
              "expiresAt": "2026-08-31T01:56:11.455Z"
            }
            """.utf8
        )
    }

    private static func sharesJSON() -> Data {
        Data(
            """
            {
              "pendingInvitations": [
                {
                  "invitationId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
                  "recipientEmail": "pending@example.com",
                  "status": "PENDING",
                  "sentAt": "2026-08-14T10:05:13.883Z",
                  "expiresAt": "2026-08-14T10:05:13.883Z"
                }
              ],
              "viewers": [
                {
                  "userId": "viewer-user-1",
                  "recipientUser": {
                    "id": "viewer-user-1",
                    "email": "viewer@example.com"
                  },
                  "grantedAt": "2026-08-14T10:05:13.883Z"
                }
              ]
            }
            """.utf8
        )
    }

    private static func revokeInvitationJSON(invitationID: String) -> Data {
        Data(
            """
            {
              "invitationId": "\(invitationID)",
              "status": "REVOKED",
              "revokedAt": "2026-08-17T04:44:42.373Z"
            }
            """.utf8
        )
    }

    private static func resendInvitationJSON(invitationID: String) -> Data {
        Data(
            """
            {
              "invitationId": "\(invitationID)",
              "invitationUrl": "https://example.com/",
              "recipientEmail": "pending@example.com",
              "expiresAt": "2026-08-17T04:53:54.132Z",
              "status": "PENDING",
              "sentAt": "2026-08-17T04:53:54.132Z"
            }
            """.utf8
        )
    }

    private static func revokeAccessJSON(projectID: String, userID: String) -> Data {
        Data(
            """
            {
              "projectId": "\(projectID)",
              "userId": "\(userID)",
              "revokedAt": "2026-08-17T04:55:15.823Z"
            }
            """.utf8
        )
    }

    private static func revokeScanAccessJSON(scanID: String, userID: String) -> Data {
        Data(
            """
            {
              "scanId": "\(scanID)",
              "userId": "\(userID)",
              "revokedAt": "2026-08-17T04:55:15.823Z"
            }
            """.utf8
        )
    }
}

private actor ShareHTTPRecorder {
    private(set) var requests: [APIEndpoint] = []

    func record(_ endpoint: APIEndpoint) {
        requests.append(endpoint)
    }
}

private struct FakeShareHTTPClient: HTTPClient {
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
