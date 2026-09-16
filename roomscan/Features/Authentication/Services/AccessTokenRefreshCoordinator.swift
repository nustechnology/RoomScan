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

        let task = Task {
            try await self.executeRefresh()
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

    func markDisplayNameUploadComplete() throws {
        guard let latest = try keychainStore.getStoredAuthData() else { return }
        try keychainStore.save(latest.withNeedsDisplayNameUpload(false))
    }

    private func executeRefresh() async throws -> StoredAuthData {
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

        let response: RefreshTokenAPIResponse = try await Self.requestWithRetry(
            httpClient: httpClient,
            endpoint: endpoint
        )

        return try persistRefreshedTokens(response: response)
    }

    private func persistRefreshedTokens(response: RefreshTokenAPIResponse) throws -> StoredAuthData {
        guard let latest = try keychainStore.getStoredAuthData() else {
            throw AuthenticationError.invalidCredential
        }

        let updated = latest.withRefreshedTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? latest.refreshToken
        )
        do {
            try keychainStore.save(updated)
            return updated
        } catch {
            throw AuthenticationError.unknown
        }
    }

    // Retries on transient network errors with exponential backoff: 1s → 2s → 4s.
    // Non-retryable errors (invalid credential, decoding, etc.) are surfaced immediately.
    private static func requestWithRetry(
        httpClient: any HTTPClient,
        endpoint: APIEndpoint,
        maxAttempts: Int = 3
    ) async throws -> RefreshTokenAPIResponse {
        let retryDelays: [UInt64] = [1_000_000_000, 2_000_000_000, 4_000_000_000]

        var lastError: AuthenticationError = .networkError
        for attempt in 0..<maxAttempts {
            try Task.checkCancellation()
            do {
                return try await httpClient.request(endpoint)
            } catch let error as HTTPClientError {
                let mapped = mapRefreshError(error)
                guard isRetryable(mapped) else {
                    throw mapped
                }
                lastError = mapped
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = .networkError
            }

            let nextAttempt = attempt + 1
            if nextAttempt < maxAttempts {
                try await Task.sleep(nanoseconds: retryDelays[attempt])
            }
        }

        throw lastError
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

            return .serverRejected(statusCode: statusCode)

        case .invalidURL, .decodingError:
            return .unknown
        }
    }

    // Whether another attempt could plausibly succeed. This is deliberately a separate
    // question from `mapRefreshError`: a rejected refresh is reported to the caller the
    // same way whether or not it was worth retrying.
    private static func isRetryable(_ error: AuthenticationError) -> Bool {
        switch error {
        case .networkError:
            return true
        case .serverRejected(let statusCode):
            return statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
        case .invalidCredential, .unavailable, .unknown, .appleSystemError, .cancelled:
            return false
        }
    }
}
