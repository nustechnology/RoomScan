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
    struct AppleSignInAttempt: Equatable {
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
    private let appleAuthorizationTimeoutNanoseconds: UInt64
    private var activeAppleSignInAttempt: AppleSignInAttempt?
    private var isCompletingAppleSignIn = false
    @ObservationIgnored private var appleAuthorizationTimeoutTask: Task<Void, Never>?

    init(
        authenticationService: any AuthenticationService,
        appleAuthorizationTimeoutNanoseconds: UInt64 = 120_000_000_000
    ) {
        self.authenticationService = authenticationService
        self.appleAuthorizationTimeoutNanoseconds = appleAuthorizationTimeoutNanoseconds
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

    /// Always supplies a nonce before the Apple authorization request is dispatched.
    /// Repeated request callbacks reuse the active nonce while the first sign-in is in progress.
    func prepareAppleSignInRequest() -> AppleSignInAttempt {
        if let activeAppleSignInAttempt {
            return activeAppleSignInAttempt
        }

        let attempt = AppleSignInAttempt(id: UUID(), rawNonce: generateRawNonce())
        activeAppleSignInAttempt = attempt
        viewState = .signingIn
        startAppleAuthorizationTimeout(for: attempt.id)
        return attempt
    }

    @discardableResult
    func completeAppleSignIn(
        authorization: ASAuthorization,
        attemptID: UUID
    ) async -> AuthenticationSession? {
        await completeAppleSignIn(attemptID: attemptID) { [authenticationService] rawNonce in
            try await authenticationService.signInWithApple(
                authorization: authorization,
                rawNonce: rawNonce
            )
        }
    }

    @discardableResult
    func completeAppleSignIn(
        attemptID: UUID,
        authenticate: (String) async throws -> AuthenticationSession
    ) async -> AuthenticationSession? {
        guard !isCompletingAppleSignIn,
              let attempt = activeAppleSignInAttempt,
              attempt.id == attemptID
        else { return nil }

        cancelAppleAuthorizationTimeout()
        isCompletingAppleSignIn = true
        defer {
            isCompletingAppleSignIn = false
            if activeAppleSignInAttempt?.id == attemptID {
                activeAppleSignInAttempt = nil
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
        guard !isCompletingAppleSignIn else { return }
        guard activeAppleSignInAttempt?.id == attemptID else { return }
        cancelAppleAuthorizationTimeout()
        activeAppleSignInAttempt = nil

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

    private func startAppleAuthorizationTimeout(for attemptID: UUID) {
        appleAuthorizationTimeoutTask?.cancel()
        let timeoutNanoseconds = appleAuthorizationTimeoutNanoseconds
        appleAuthorizationTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
            } catch {
                return
            }

            guard let self,
                  !self.isCompletingAppleSignIn,
                  self.activeAppleSignInAttempt?.id == attemptID
            else { return }

            self.activeAppleSignInAttempt = nil
            self.appleAuthorizationTimeoutTask = nil
            self.handleError(.appleSystemError)
        }
    }

    private func cancelAppleAuthorizationTimeout() {
        appleAuthorizationTimeoutTask?.cancel()
        appleAuthorizationTimeoutTask = nil
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
