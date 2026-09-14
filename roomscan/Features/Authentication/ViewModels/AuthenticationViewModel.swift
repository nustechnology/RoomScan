//
//  AuthenticationViewModel.swift
//  roomscan
//

import AuthenticationServices
import CryptoKit
import Foundation
import Observation

@MainActor
@Observable
final class AuthenticationViewModel {
    struct AppleAuthorizationAttempt: Equatable {
        let id: UUID
        let rawNonce: String
    }

    enum ViewState: Equatable {
        case idle
        case signingIn
        case failed(AuthenticationError)
    }

    private(set) var viewState: ViewState = .idle
    var toastMessage: String?
    var toastStyle: ToastStyle = .error

    private let authenticationService: any AuthenticationService
    private var activeAppleAuthorizationAttempt: AppleAuthorizationAttempt?

    init(authenticationService: any AuthenticationService) {
        self.authenticationService = authenticationService
    }

    var isSigningIn: Bool {
        if isAppleAuthorizationInProgress { return true }
        if case .signingIn = viewState { return true }
        return false
    }

    var isAppleAuthorizationInProgress: Bool {
        activeAppleAuthorizationAttempt != nil
    }

    var errorMessage: String? {
        if case .failed(let error) = viewState {
            return error.localizedDescription
        }
        return nil
    }

    func generateRawNonce() -> String {
        var randomBytes = [UInt8](repeating: 0, count: 32)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate random bytes: \(errorCode)")
        }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { charset[Int($0) % charset.count] }
        return String(nonce)
    }

    func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }

    func beginAppleAuthorization() -> AppleAuthorizationAttempt {
        if let activeAppleAuthorizationAttempt {
            return activeAppleAuthorizationAttempt
        }

        let attempt = AppleAuthorizationAttempt(id: UUID(), rawNonce: generateRawNonce())
        activeAppleAuthorizationAttempt = attempt
        return attempt
    }

    func endAppleAuthorization(attemptID: UUID) {
        guard activeAppleAuthorizationAttempt?.id == attemptID else { return }
        activeAppleAuthorizationAttempt = nil
    }

    @discardableResult
    func signInWithApple(
        authorization: ASAuthorization,
        attemptID: UUID
    ) async -> AuthenticationSession? {
        await signInWithApple(attemptID: attemptID) { [authenticationService] rawNonce in
            try await authenticationService.signInWithApple(
                authorization: authorization,
                rawNonce: rawNonce
            )
        }
    }

    @discardableResult
    func signInWithApple(
        attemptID: UUID,
        authenticate: (String) async throws -> AuthenticationSession
    ) async -> AuthenticationSession? {
        guard !isCredentialExchangeInProgress,
              let attempt = activeAppleAuthorizationAttempt,
              attempt.id == attemptID
        else { return nil }

        viewState = .signingIn
        defer {
            if activeAppleAuthorizationAttempt?.id == attemptID {
                activeAppleAuthorizationAttempt = nil
            }
        }

        do {
            let session = try await authenticate(attempt.rawNonce)
            viewState = .idle
            return session
        } catch let error as AuthenticationError {
            handleError(error)
            return nil
        } catch {
            handleError(.unknown)
            return nil
        }
    }

    func handleAppleSignInError(_ error: Error, attemptID: UUID) {
        guard !isCredentialExchangeInProgress,
              activeAppleAuthorizationAttempt?.id == attemptID
        else { return }
        endAppleAuthorization(attemptID: attemptID)

        if let authError = error as? ASAuthorizationError {
            if authError.code == .canceled {
                viewState = .idle
            } else {
                handleError(.appleSystemError)
            }
        } else if let authError = error as? AuthenticationError {
            handleError(authError)
        } else {
            handleError(.unknown)
        }
    }

    /// Returns a session on success. Cancellation leaves idle state and returns nil.
    @discardableResult
    func signInWithApple() async -> AuthenticationSession? {
        guard !isSigningIn else { return nil }

        viewState = .signingIn

        do {
            let session = try await authenticationService.signIn(with: .apple)
            viewState = .idle
            return session
        } catch let error as AuthenticationError {
            handleError(error)
            return nil
        } catch {
            handleError(.unknown)
            return nil
        }
    }

    private func handleError(_ error: AuthenticationError) {
        if error == .cancelled {
            viewState = .idle
        } else {
            viewState = .failed(error)
            toastMessage = error.errorDescription
            toastStyle = .error
        }
    }

    private var isCredentialExchangeInProgress: Bool {
        if case .signingIn = viewState { return true }
        return false
    }

    func dismissError() {
        viewState = .idle
        toastMessage = nil
    }

    @discardableResult
    func retrySignIn() async -> AuthenticationSession? {
        await signInWithApple()
    }
}
