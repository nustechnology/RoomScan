//
//  AuthenticatedHTTPClient.swift
//  roomscan
//

import Foundation

nonisolated struct AuthenticatedHTTPClient: HTTPClient {
    private let httpClient: any HTTPClient
    private let keychainStore: any KeychainTokenStore
    private let refreshCoordinator: AccessTokenRefreshCoordinator
    private let onSessionInvalidated: (@MainActor @Sendable () -> Void)?

    init(
        httpClient: any HTTPClient,
        keychainStore: any KeychainTokenStore,
        refreshCoordinator: AccessTokenRefreshCoordinator? = nil,
        onSessionInvalidated: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.httpClient = httpClient
        self.keychainStore = keychainStore
        self.refreshCoordinator = refreshCoordinator ?? AccessTokenRefreshCoordinator(
            httpClient: httpClient,
            keychainStore: keychainStore
        )
        self.onSessionInvalidated = onSessionInvalidated
    }

    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        guard let storedData = try keychainStore.getStoredAuthData() else {
            throw HTTPClientError.serverError(statusCode: 401, apiError: nil)
        }

        let authenticatedEndpoint = endpoint.addingHeader(
            key: "Authorization",
            value: "Bearer \(storedData.accessToken)"
        )

        do {
            return try await httpClient.request(authenticatedEndpoint)
        } catch let error as HTTPClientError {
            guard shouldRefresh(for: error) else {
                throw error
            }

            let refreshedData: StoredAuthData
            do {
                refreshedData = try await refreshCoordinator.refreshTokens()
            } catch let authError as AuthenticationError {
                if authError == .invalidCredential {
                    await clearInvalidSession()
                    throw error
                }
                throw mapRefreshFailure(authError, originalError: error)
            }

            let retriedEndpoint = endpoint.addingHeader(
                key: "Authorization",
                value: "Bearer \(refreshedData.accessToken)"
            )
            return try await httpClient.request(retriedEndpoint)
        }
    }

    /// Deletes tokens and notifies `AppState` in one MainActor turn so callers cannot
    /// observe an empty keychain while `phase` is still `.signedIn`.
    @MainActor
    private func clearInvalidSession() {
        try? keychainStore.deleteTokens()
        onSessionInvalidated?()
    }

    private func shouldRefresh(for error: HTTPClientError) -> Bool {
        guard case .serverError(let statusCode, let apiError) = error else {
            return false
        }
        if statusCode == 401 {
            return true
        }
        if statusCode == 403 {
            return isTokenError(apiError)
        }
        return false
    }

    private func isTokenError(_ apiError: APIErrorResponse?) -> Bool {
        guard let code = apiError?.error.code else {
            return false
        }
        switch code {
        case "INVALID_TOKEN", "TOKEN_EXPIRED", "INVALID_CREDENTIAL":
            return true
        default:
            return false
        }
    }

    private func mapRefreshFailure(
        _ error: AuthenticationError,
        originalError: HTTPClientError
    ) -> HTTPClientError {
        switch error {
        case .networkError:
            return .networkError
        case .invalidCredential:
            return .serverError(statusCode: 401, apiError: nil)
        case .serverRejected(let statusCode):
            return .serverError(statusCode: statusCode, apiError: nil)
        case .unknown, .unavailable, .appleSystemError, .appleAuthorizationTimedOut, .cancelled:
            // Refresh failed for a reason with no HTTP equivalent (keychain access, a
            // malformed refresh payload). The caller's request still failed for its own
            // reason, so report that rather than inventing a category.
            return originalError
        }
    }
}
