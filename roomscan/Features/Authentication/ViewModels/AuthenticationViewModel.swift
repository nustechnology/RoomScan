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
    private let appleAuthorizationTimeoutNanoseconds: UInt64
    private let appleAuthorizationExpiryNanoseconds: UInt64
    private var activeAppleAuthorizationAttempt: AppleAuthorizationAttempt?
    /// The attempt that timed out but can still complete if Apple calls back before it expires.
    /// At most one exists: `beginAppleAuthorization` clears it before creating a new attempt.
    /// The live `ASAuthorizationController` is intentionally not cancelled here —
    /// `cancel()` does not reliably dismiss Apple's sheet, and dropping the controller
    /// context would discard a late successful credential from that same sheet.
    private var timedOutAppleAuthorizationAttempt: AppleAuthorizationAttempt?
    /// An attempt whose grace period ended. Kept so a later sheet completion can tell the user
    /// to try again, without retaining the nonce.
    private var expiredAppleAuthorizationAttemptID: UUID?
    @ObservationIgnored private var appleAuthorizationTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var timedOutAppleAuthorizationExpiryTask: Task<Void, Never>?

    init(
        authenticationService: any AuthenticationService,
        appleAuthorizationTimeoutNanoseconds: UInt64 = 120_000_000_000,
        appleAuthorizationExpiryNanoseconds: UInt64 = 600_000_000_000
    ) {
        self.authenticationService = authenticationService
        self.appleAuthorizationTimeoutNanoseconds = appleAuthorizationTimeoutNanoseconds
        self.appleAuthorizationExpiryNanoseconds = appleAuthorizationExpiryNanoseconds
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

        cancelTimedOutAppleAuthorizationExpiry()
        timedOutAppleAuthorizationAttempt = nil
        expiredAppleAuthorizationAttemptID = nil
        let attempt = AppleAuthorizationAttempt(id: UUID(), rawNonce: generateRawNonce())
        activeAppleAuthorizationAttempt = attempt
        startAppleAuthorizationTimeout(for: attempt.id)
        return attempt
    }

    func endAppleAuthorization(attemptID: UUID) {
        clearTimedOutAppleAuthorizationAttempt(attemptID: attemptID)
        guard activeAppleAuthorizationAttempt?.id == attemptID else { return }
        cancelAppleAuthorizationTimeout()
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
        guard !isCredentialExchangeInProgress else {
            consumeExpiredAppleAuthorizationAttempt(attemptID: attemptID)
            return nil
        }
        guard let attempt = appleAuthorizationAttempt(for: attemptID) else {
            if consumeExpiredAppleAuthorizationAttempt(attemptID: attemptID) {
                handleError(.appleSystemError)
            }
            return nil
        }

        cancelAppleAuthorizationTimeout()
        viewState = .signingIn
        defer {
            clearTimedOutAppleAuthorizationAttempt(attemptID: attemptID)
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
        let removedCompletableAttempt = clearTimedOutAppleAuthorizationAttempt(attemptID: attemptID)
        let isExpiredAttempt = consumeExpiredAppleAuthorizationAttempt(attemptID: attemptID)
        guard !isCredentialExchangeInProgress else { return }
        guard activeAppleAuthorizationAttempt?.id == attemptID else {
            guard removedCompletableAttempt != nil || isExpiredAttempt else { return }
            reportAppleSignInFailure(error)
            return
        }
        endAppleAuthorization(attemptID: attemptID)
        reportAppleSignInFailure(error)
    }

    private func reportAppleSignInFailure(_ error: Error) {
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

    private func appleAuthorizationAttempt(for attemptID: UUID) -> AppleAuthorizationAttempt? {
        if let activeAppleAuthorizationAttempt {
            return activeAppleAuthorizationAttempt.id == attemptID ? activeAppleAuthorizationAttempt : nil
        }
        return timedOutAppleAuthorizationAttempt?.id == attemptID ? timedOutAppleAuthorizationAttempt : nil
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
                  !self.isCredentialExchangeInProgress,
                  let attempt = self.activeAppleAuthorizationAttempt,
                  attempt.id == attemptID
            else { return }

            // Unlock the button only. Do not cancel the ASAuthorizationController: Apple's
            // password sheet often stays up after cancel(), and a late submit from that
            // sheet must still be able to exchange the retained nonce during the grace period.
            self.activeAppleAuthorizationAttempt = nil
            self.timedOutAppleAuthorizationAttempt = attempt
            self.appleAuthorizationTimeoutTask = nil
            self.startTimedOutAppleAuthorizationExpiry(for: attempt.id)
        }
    }

    private func startTimedOutAppleAuthorizationExpiry(for attemptID: UUID) {
        timedOutAppleAuthorizationExpiryTask?.cancel()
        let expiryNanoseconds = appleAuthorizationExpiryNanoseconds
        timedOutAppleAuthorizationExpiryTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: expiryNanoseconds)
            } catch {
                return
            }

            guard let self,
                  self.timedOutAppleAuthorizationAttempt?.id == attemptID
            else { return }

            self.timedOutAppleAuthorizationAttempt = nil
            self.expiredAppleAuthorizationAttemptID = attemptID
            self.timedOutAppleAuthorizationExpiryTask = nil
        }
    }

    @discardableResult
    private func clearTimedOutAppleAuthorizationAttempt(attemptID: UUID) -> AppleAuthorizationAttempt? {
        guard timedOutAppleAuthorizationAttempt?.id == attemptID else { return nil }
        cancelTimedOutAppleAuthorizationExpiry()
        let attempt = timedOutAppleAuthorizationAttempt
        timedOutAppleAuthorizationAttempt = nil
        return attempt
    }

    @discardableResult
    private func consumeExpiredAppleAuthorizationAttempt(attemptID: UUID) -> Bool {
        guard expiredAppleAuthorizationAttemptID == attemptID else { return false }
        expiredAppleAuthorizationAttemptID = nil
        return true
    }

    private func cancelTimedOutAppleAuthorizationExpiry() {
        timedOutAppleAuthorizationExpiryTask?.cancel()
        timedOutAppleAuthorizationExpiryTask = nil
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
