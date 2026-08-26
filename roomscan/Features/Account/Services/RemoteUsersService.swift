//
//  RemoteUsersService.swift
//  roomscan
//

import Foundation

final class RemoteUsersService: UsersService, @unchecked Sendable {
    private let httpClient: any HTTPClient

    init(httpClient: any HTTPClient) {
        self.httpClient = httpClient
    }

    func fetchMe(fallingBackTo currentUser: AuthenticatedUser) async throws -> AuthenticatedUser {
        let endpoint = APIEndpoint(path: "/api/v1/users/me", method: .get)

        do {
            let response: UserMeAPIResponse = try await httpClient.request(endpoint)
            return response.toAuthenticatedUser(fallingBackTo: currentUser)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as HTTPClientError {
            throw mapHTTPError(error)
        } catch {
            throw UsersServiceError.network
        }
    }

    func updateMe(
        displayName: String,
        fallingBackTo currentUser: AuthenticatedUser
    ) async throws -> AuthenticatedUser {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw UsersServiceError.invalidDisplayName
        }

        let requestBody = UpdateUserMeAPIRequest(displayName: trimmed)
        let body: Data
        do {
            body = try JSONEncoder().encode(requestBody)
        } catch {
            #if DEBUG
            print("[RemoteUsersService] updateMe encode failed: \(error)")
            #endif
            throw UsersServiceError.network
        }

        let endpoint = APIEndpoint(
            path: "/api/v1/users/me",
            method: .patch,
            body: body
        )

        do {
            let response: UserMeAPIResponse = try await httpClient.request(endpoint)
            return response.toAuthenticatedUser(fallingBackTo: currentUser)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as HTTPClientError {
            throw mapHTTPError(error)
        } catch let error as UsersServiceError {
            throw error
        } catch {
            throw UsersServiceError.network
        }
    }

    private func mapHTTPError(_ error: HTTPClientError) -> UsersServiceError {
        switch error {
        case .networkError, .invalidURL:
            return .network
        case .serverError(let statusCode, _):
            switch statusCode {
            case 400:
                return .invalidDisplayName
            case 401:
                return .unauthorized
            case 404:
                return .notFound
            default:
                return .server
            }
        case .decodingError(_, let bodyPreview):
            #if DEBUG
            print("[RemoteUsersService] decodingError bodyBytes=\(bodyPreview.utf8.count)")
            #endif
            return .server
        }
    }
}
