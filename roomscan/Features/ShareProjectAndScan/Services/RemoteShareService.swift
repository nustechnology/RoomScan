//
//  RemoteShareService.swift
//  roomscan
//

import Foundation
import UIKit

/// Network-backed share service.
/// Load uses `GET /api/v1/projects/{projectId}/shares`.
/// Invite People uses `POST /api/v1/projects/{projectId}/invitations`.
/// Scan sharing uses the equivalent `/api/v1/scans/{scanId}/...` endpoints.
/// Resend invitation uses `POST /api/v1/invitations/{invitationId}/resend`.
/// Cancel invitation uses `DELETE /api/v1/invitations/{invitationId}`.
/// Remove access uses the corresponding project or scan `/shares/{userId}` endpoint.
actor RemoteShareService: ShareService {
    static let defaultInvitationLifetimeSeconds = 7 * 24 * 60 * 60

    private let httpClient: any HTTPClient
    private let invitationLifetimeSeconds: Int
    private var membersByInputID: [String: [InvitedMember]] = [:]

    init(
        httpClient: any HTTPClient,
        invitationLifetimeSeconds: Int = RemoteShareService.defaultInvitationLifetimeSeconds
    ) {
        self.httpClient = httpClient
        self.invitationLifetimeSeconds = invitationLifetimeSeconds
    }

    func loadInvitedMembers(for input: ShareScreenInput) async throws -> ShareMembersSnapshot {
        let endpoint = APIEndpoint(
            path: "\(shareTargetPath(for: input))/shares",
            method: .get
        )

        do {
            let response: ProjectSharesAPIResponse = try await httpClient.request(endpoint)
            let members = ShareAPIMapping.toMembers(response)
            membersByInputID[input.id] = members
            return ShareMembersSnapshot(members: members, isOffline: false)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as HTTPClientError {
            throw mapHTTPClientError(error, forLoad: true)
        } catch {
            throw ShareServiceError.unavailable
        }
    }

    func sendInvitation(for input: ShareScreenInput, email: String) async throws -> InvitedMember {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        let existingMembers = membersByInputID[input.id, default: []]
        if existingMembers.contains(where: {
            $0.email.caseInsensitiveCompare(normalizedEmail) == .orderedSame
        }) {
            throw ShareServiceError.duplicateEmail
        }

        let requestBody = CreateProjectInvitationAPIRequest(
            recipientEmail: normalizedEmail,
            expiresInSeconds: invitationLifetimeSeconds
        )
        let body: Data
        do {
            body = try JSONEncoder().encode(requestBody)
        } catch {
            throw ShareServiceError.unavailable
        }

        let endpoint = APIEndpoint(
            path: "\(shareTargetPath(for: input))/invitations",
            method: .post,
            body: body,
            idempotencyKey: UUID().uuidString
        )

        do {
            let response: CreateProjectInvitationAPIResponse = try await httpClient.request(endpoint)
            let member = ShareAPIMapping.toInvitedMember(response)
            membersByInputID[input.id, default: []].insert(member, at: 0)
            return member
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as HTTPClientError {
            throw mapHTTPClientError(error, forLoad: false)
        } catch {
            throw ShareServiceError.unavailable
        }
    }

    func resendInvitation(for input: ShareScreenInput, id: String) async throws -> InvitedMember {
        let endpoint = APIEndpoint(
            path: "/api/v1/invitations/\(id)/resend",
            method: .post
        )

        do {
            let response: CreateProjectInvitationAPIResponse = try await httpClient.request(endpoint)
            let member = ShareAPIMapping.toInvitedMember(response)
            if var members = membersByInputID[input.id],
               let index = members.firstIndex(where: { $0.id == id || $0.id == member.id }) {
                members[index] = member
                membersByInputID[input.id] = members
            } else {
                membersByInputID[input.id, default: []].insert(member, at: 0)
            }
            return member
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as HTTPClientError {
            throw mapHTTPClientError(error, forLoad: false)
        } catch {
            throw ShareServiceError.unavailable
        }
    }

    func revokeInvitation(for input: ShareScreenInput, id: String) async throws {
        let endpoint = APIEndpoint(
            path: "/api/v1/invitations/\(id)",
            method: .delete
        )

        do {
            let _: RevokeInvitationAPIResponse = try await httpClient.request(endpoint)
            if var members = membersByInputID[input.id] {
                members.removeAll { $0.id == id }
                membersByInputID[input.id] = members
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as HTTPClientError {
            throw mapHTTPClientError(error, forLoad: false)
        } catch {
            throw ShareServiceError.unavailable
        }
    }

    func revokeAccess(for input: ShareScreenInput, userID: String) async throws {
        let endpoint = APIEndpoint(
            path: "\(shareTargetPath(for: input))/shares/\(userID)",
            method: .delete
        )

        do {
            let _: RevokeShareAPIResponse = try await httpClient.request(endpoint)
            if var members = membersByInputID[input.id] {
                members.removeAll { $0.id == userID }
                membersByInputID[input.id] = members
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as HTTPClientError {
            throw mapHTTPClientError(error, forLoad: false)
        } catch {
            throw ShareServiceError.unavailable
        }
    }

    func copyInvitationLink(for input: ShareScreenInput) async throws -> URL {
        let endpoint = APIEndpoint(
            path: "\(shareTargetPath(for: input))/share-links",
            method: .post,
            idempotencyKey: UUID().uuidString
        )

        do {
            let response: CreateShareLinkAPIResponse = try await httpClient.request(endpoint)
            guard let url = URL(string: response.shareLinkUrl) else {
                throw ShareServiceError.unavailable
            }
            await MainActor.run {
                UIPasteboard.general.string = url.absoluteString
            }
            return url
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as HTTPClientError {
            throw mapHTTPClientError(error, forLoad: false)
        } catch let error as ShareServiceError {
            throw error
        } catch {
            throw ShareServiceError.unavailable
        }
    }

    private func shareTargetPath(for input: ShareScreenInput) -> String {
        switch input.target {
        case .project(let target):
            return "/api/v1/projects/\(target.projectID)"
        case .scan(let target):
            return "/api/v1/scans/\(target.scanID)"
        }
    }

    private func mapHTTPClientError(_ error: HTTPClientError, forLoad: Bool) -> ShareServiceError {
        switch error {
        case .networkError, .invalidURL:
            return .offline
        case .decodingError:
            return .unavailable
        case .serverError(let statusCode, let apiError):
            if forLoad {
                return .unavailable
            }
            switch statusCode {
            case 400, 409:
                if isDuplicateInvitation(apiError) {
                    return .duplicateEmail
                }
                return .unavailable
            case 404:
                return .memberNotFound
            default:
                return .unavailable
            }
        }
    }

    private func isDuplicateInvitation(_ apiError: APIErrorResponse?) -> Bool {
        let code = apiError?.error.code.uppercased() ?? ""
        let message = apiError?.error.message.uppercased() ?? ""
        return code.contains("DUPLICATE")
            || message.contains("DUPLICATE")
            || message.contains("ALREADY")
    }
}
