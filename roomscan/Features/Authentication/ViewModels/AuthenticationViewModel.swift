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
    enum ViewState: Equatable {
        case idle
        case signingIn
        case failed(AuthenticationError)
    }

    private(set) var viewState: ViewState = .idle
    var toastMessage: String?

    private let authenticationService: any AuthenticationService

    init(authenticationService: any AuthenticationService) {
        self.authenticationService = authenticationService
    }

    var isSigningIn: Bool {
        if case .signingIn = viewState { return true }
        return false
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

    @discardableResult
    func signInWithApple(authorization: ASAuthorization, rawNonce: String) async -> AuthenticationSession? {
        guard !isSigningIn else { return nil }

        viewState = .signingIn

        do {
            let session = try await authenticationService.signInWithApple(authorization: authorization, rawNonce: rawNonce)
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

    func handleAppleSignInError(_ error: Error) {
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
        }
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
