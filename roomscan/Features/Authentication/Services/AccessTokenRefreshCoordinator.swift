//
//  AccessTokenRefreshCoordinator.swift
//  roomscan
//

import Foundation

actor AccessTokenRefreshCoordinator {
    private let httpClient: any HTTPClient
    private let keychainStore: any KeychainTokenStore
    private var refreshTask: Task<StoredAuthData, Error>?

    init(
        httpClient: any HTTPClient,
        keychainStore: any KeychainTokenStore
    ) {
        self.httpClient = httpClient
        self.keychainStore = keychainStore
    }

    func refreshTokens() async throws -> StoredAuthData {
        if let refreshTask {
            return try await refreshTask.value
        }

        let task = Task { [httpClient, keychainStore] in
            let storedData: StoredAuthData
            do {
                guard let existingData = try keychainStore.getStoredAuthData() else {
                    throw AuthenticationError.invalidCredential
                }
                storedData = existingData
            } catch let error as AuthenticationError {
                throw error
            } catch {
                throw AuthenticationError.unknown
            }

            guard !storedData.refreshToken.isEmpty else {
                throw AuthenticationError.invalidCredential
            }

            let body = try JSONEncoder().encode(
                RefreshTokenAPIRequest(refreshToken: storedData.refreshToken)
            )
            let endpoint = APIEndpoint(
                path: "/api/v1/auth/refresh",
                method: .post,
                body: body
            )

            let response: RefreshTokenAPIResponse
            do {
                response = try await httpClient.request(endpoint)
            } catch let error as HTTPClientError {
                throw Self.mapRefreshError(error)
            } catch {
                throw AuthenticationError.networkError
            }

            let updatedData = StoredAuthData(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken ?? storedData.refreshToken,
                userId: storedData.userId,
                userEmail: storedData.userEmail
            )

            do {
                try keychainStore.save(updatedData)
            } catch {
                throw AuthenticationError.unknown
            }

            return updatedData
        }

        refreshTask = task

        do {
            let refreshedData = try await task.value
            refreshTask = nil
            return refreshedData
        } catch {
            refreshTask = nil
            throw error
        }
    }

    private static func mapRefreshError(_ error: HTTPClientError) -> AuthenticationError {
        switch error {
        case .networkError:
            return .networkError

        case .serverError(let statusCode, let apiError):
            if statusCode == 401 || statusCode == 403 {
                return .invalidCredential
            }

            if let code = apiError?.error.code {
                switch code {
                case "INVALID_REFRESH_TOKEN", "REFRESH_TOKEN_EXPIRED", "INVALID_TOKEN", "TOKEN_EXPIRED":
                    return .invalidCredential
                default:
                    break
                }
            }

            return .networkError

        case .invalidURL, .decodingError:
            return .unknown
        }
    }
}
