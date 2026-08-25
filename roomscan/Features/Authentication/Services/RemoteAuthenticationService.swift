//
//  RemoteAuthenticationService.swift
//  roomscan
//

import AuthenticationServices
import Foundation

@MainActor
final class RemoteAuthenticationService: AuthenticationService {
    private let httpClient: any HTTPClient
    private let keychainStore: any KeychainTokenStore
    private let refreshCoordinator: AccessTokenRefreshCoordinator

    init(
        httpClient: any HTTPClient,
        keychainStore: any KeychainTokenStore,
        refreshCoordinator: AccessTokenRefreshCoordinator? = nil
    ) {
        self.httpClient = httpClient
        self.keychainStore = keychainStore
        self.refreshCoordinator = refreshCoordinator ?? AccessTokenRefreshCoordinator(
            httpClient: httpClient,
            keychainStore: keychainStore
        )
    }

    // MARK: - Session Restoration

    func restoreSession() async throws -> AuthenticationSession? {
        guard try keychainStore.getStoredAuthData() != nil else {
            return nil
        }

        do {
            let refreshedData = try await refreshCoordinator.refreshTokens()
            return makeSession(from: refreshedData)
        } catch let error as AuthenticationError {
            if error == .invalidCredential {
                try? keychainStore.deleteTokens()
                return nil
            }
            throw error
        }
    }

    private func makeSession(from storedData: StoredAuthData) -> AuthenticationSession {
        AuthenticationSession(
            user: AuthenticatedUser(
                id: storedData.userId,
                displayName: nil,
                email: storedData.userEmail
            ),
            provider: .apple
        )
    }

    // MARK: - Direct Sign-In (Not Supported)

    func signIn(with provider: AuthenticationProvider) async throws -> AuthenticationSession {
        switch provider {
        case .apple:
            throw AuthenticationError.invalidCredential
        case .google, .facebook:
            throw AuthenticationError.unavailable
        }
    }

    // MARK: - Sign in with Apple

    func signInWithApple(
        authorization: ASAuthorization,
        rawNonce: String
    ) async throws -> AuthenticationSession {
        guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = appleCredential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8)
        else {
            throw AuthenticationError.invalidCredential
        }

        let endpoint = buildAppleAuthEndpoint(identityToken: identityToken, nonce: rawNonce)

        let response: AuthAPIResponse
        do {
            response = try await httpClient.request(endpoint)
        } catch let error as HTTPClientError {
            throw mapHTTPClientError(error)
        } catch {
            throw AuthenticationError.networkError
        }

        let user = AuthenticatedUser(
            id: response.user.id,
            displayName: nil,
            email: response.user.email
        )
        let provider = AuthenticationProvider(rawValue: response.user.provider) ?? .apple

        let storedData = StoredAuthData(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            userId: response.user.id,
            userEmail: response.user.email
        )
        do {
            try keychainStore.save(storedData)
        } catch {
            throw AuthenticationError.unknown
        }

        return AuthenticationSession(
            user: user,
            provider: provider
        )
    }

    // MARK: - Sign Out

    func signOut() async throws {
        try keychainStore.deleteTokens()
    }

    // MARK: - Private Helpers

    private func buildAppleAuthEndpoint(identityToken: String, nonce: String) -> APIEndpoint {
        let requestBody = AuthAPIRequest(identityToken: identityToken, nonce: nonce)
        let body = try? JSONEncoder().encode(requestBody)

        return APIEndpoint(
            path: "/api/v1/auth/apple",
            method: .post,
            body: body
        )
    }

    private func mapHTTPClientError(_ error: HTTPClientError) -> AuthenticationError {
        switch error {
        case .networkError:
            return .networkError

        case .serverError(let statusCode, let apiError):
            if statusCode == 401 || statusCode == 403 {
                return .invalidCredential
            }
            if let errorBody = apiError?.error {
                switch errorBody.code {
                case "INVALID_TOKEN", "TOKEN_EXPIRED", "INVALID_CREDENTIAL", "INVALID_APPLE_IDENTITY_TOKEN":
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
