//
//  RemoteInvitationService.swift
//  roomscan
//

import Foundation

/// Network-backed invitation service.
/// Preview uses `GET /api/v1/invitations/{token}`.
actor RemoteInvitationService: InvitationService {
    private let httpClient: any HTTPClient

    init(httpClient: any HTTPClient) {
        self.httpClient = httpClient
    }

    func fetchInvitation(
        scope: InvitationScope,
        token: String,
        currentUserEmail: String?
    ) async throws -> InvitationDetails {
        guard let token = InvitationTokenValidator.sanitized(token) else {
            throw InvitationServiceError.unavailable
        }
        let endpoint = invitationEndpoint(token: token, suffix: nil, method: .get)

        do {
            let response: InvitationPreviewAPIResponse = try await httpClient.request(endpoint)
            try throwIfPreviewUnavailable(response, currentUserEmail: currentUserEmail)
            return try InvitationAPIMapping.toInvitationDetails(
                token: token,
                scope: scope,
                response: response
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as InvitationServiceError {
            throw error
        } catch let error as HTTPClientError {
            throw mapHTTPClientError(error)
        } catch {
            throw InvitationServiceError.unavailable
        }
    }

    func acceptInvitation(
        scope: InvitationScope,
        token: String,
        currentUserEmail _: String?
    ) async throws -> AcceptedInvitationDestination {
        guard let token = InvitationTokenValidator.sanitized(token) else {
            throw InvitationServiceError.unavailable
        }
        let endpoint = invitationEndpoint(token: token, suffix: "accept", method: .post)

        do {
            let response: AcceptInvitationAPIResponse = try await httpClient.request(endpoint)
            return try InvitationAPIMapping.toAcceptedDestination(response, scope: scope)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as InvitationServiceError {
            throw error
        } catch let error as HTTPClientError {
            throw mapHTTPClientError(error)
        } catch {
            throw InvitationServiceError.unavailable
        }
    }

    func declineInvitation(
        scope _: InvitationScope,
        token: String,
        currentUserEmail _: String?
    ) async throws {
        guard let token = InvitationTokenValidator.sanitized(token) else {
            throw InvitationServiceError.unavailable
        }
        let endpoint = invitationEndpoint(token: token, suffix: "decline", method: .post)

        do {
            let _: DeclineInvitationAPIResponse = try await httpClient.request(endpoint)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as HTTPClientError {
            throw mapHTTPClientError(error)
        } catch {
            throw InvitationServiceError.unavailable
        }
    }

    private func invitationEndpoint(
        token: String,
        suffix: String?,
        method: HTTPMethod
    ) -> APIEndpoint {
        let path: String
        if let suffix {
            path = "/api/v1/invitations/\(token)/\(suffix)"
        } else {
            path = "/api/v1/invitations/\(token)"
        }
        return APIEndpoint(path: path, method: method)
    }

    private func throwIfPreviewUnavailable(
        _ response: InvitationPreviewAPIResponse,
        currentUserEmail: String?
    ) throws {
        switch response.status.uppercased() {
        case "PENDING", "ACTIVE":
            if response.expiresAt <= Date() {
                throw InvitationServiceError.expired
            }
            if let recipientEmail = normalizedEmail(response.recipientEmail),
               normalizedEmail(currentUserEmail) != recipientEmail {
                throw InvitationServiceError.accessDenied
            }
        case "ACCEPTED":
            throw InvitationServiceError.alreadyAccepted
        case "DECLINED":
            throw InvitationServiceError.declined
        case "EXPIRED":
            throw InvitationServiceError.expired
        case "REVOKED":
            throw InvitationServiceError.unavailable
        default:
            throw InvitationServiceError.unavailable
        }
    }

    private func normalizedEmail(_ email: String?) -> String? {
        guard let email else { return nil }
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func mapHTTPClientError(_ error: HTTPClientError) -> InvitationServiceError {
        switch error {
        case .networkError, .invalidURL:
            return .network
        case .decodingError:
            return .unavailable
        case .serverError(let statusCode, _):
            switch statusCode {
            case 404:
                return .notFound
            case 401, 403:
                return .accessDenied
            default:
                return .unavailable
            }
        }
    }
}
