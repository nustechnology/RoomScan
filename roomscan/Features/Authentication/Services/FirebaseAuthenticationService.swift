//
//  FirebaseAuthenticationService.swift
//  roomscan
//

import AuthenticationServices
import FirebaseAuth
import Foundation

@MainActor
final class FirebaseAuthenticationService: AuthenticationService {
    func restoreSession() async throws -> AuthenticationSession? {
        guard let firebaseUser = Auth.auth().currentUser else {
            return nil
        }
        return firebaseUser.toAuthenticationSession()
    }

    func signIn(with provider: AuthenticationProvider) async throws -> AuthenticationSession {
        switch provider {
        case .apple:
            // Direct sign in with Apple on Firebase requires an ASAuthorization credential via signInWithApple(authorization:rawNonce:)
            throw AuthenticationError.invalidCredential
        case .google, .facebook:
            throw AuthenticationError.unavailable
        }
    }

    func signInWithApple(authorization: ASAuthorization, rawNonce: String) async throws -> AuthenticationSession {
        guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = appleCredential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            throw AuthenticationError.invalidCredential
        }

        let credential = OAuthProvider.appleCredential(
            withIDToken: identityToken,
            rawNonce: rawNonce,
            fullName: appleCredential.fullName
        )

        do {
            let authResult = try await Auth.auth().signIn(with: credential)
            return authResult.user.toAuthenticationSession()
        } catch let authError as AuthenticationError {
            throw authError
        } catch {
            throw mapFirebaseError(error)
        }
    }

    func signOut() async throws {
        do {
            try Auth.auth().signOut()
        } catch {
            throw AuthenticationError.unknown
        }
    }

    private func mapFirebaseError(_ error: Error) -> AuthenticationError {
        let nsError = error as NSError
        if nsError.domain == AuthErrorDomain {
            if let errorCode = AuthErrorCode(rawValue: nsError.code) {
                switch errorCode {
                case .networkError:
                    return .networkError
                case .invalidCredential, .userTokenExpired, .invalidUserToken:
                    return .invalidCredential
                default:
                    break
                }
            }
        }
        return .unknown
    }
}

extension FirebaseAuth.User {
    func toAuthenticationSession() -> AuthenticationSession {
        AuthenticationSession(
            user: AuthenticatedUser(
                id: uid,
                displayName: displayName,
                email: email
            ),
            provider: .apple
        )
    }
}
