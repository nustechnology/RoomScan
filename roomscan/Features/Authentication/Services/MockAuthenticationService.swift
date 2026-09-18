//
//  MockAuthenticationService.swift
//  roomscan
//

import AuthenticationServices
import Foundation

/// Deterministic in-memory authentication used for development, previews, and tests.
/// Not a production Sign in with Apple implementation.
@MainActor
final class MockAuthenticationService: AuthenticationService {
    enum SignInOutcome: Equatable, Sendable {
        case success
        case cancelled
        case appleSystemError
        case invalidCredential
        case networkError
        case failure
    }

    struct Configuration: Equatable, Sendable {
        var initialSession: AuthenticationSession?
        var signInOutcome: SignInOutcome
        var restoreFails: Bool
        var simulatedDelayNanoseconds: UInt64

        /// Nonisolated so it can be used as a default argument (evaluated outside the main actor).
        nonisolated static let `default` = Configuration(
            initialSession: nil,
            signInOutcome: .success,
            restoreFails: false,
            simulatedDelayNanoseconds: 300_000_000
        )
    }

    private var session: AuthenticationSession?
    private let configuration: Configuration
    private var hasSignInStarted = false
    private var signInStartedContinuations: [CheckedContinuation<Void, Never>] = []

    init(configuration: Configuration = .default) {
        self.configuration = configuration
        self.session = configuration.initialSession
    }

    /// Suspends until `signIn(with:)` has been entered (and any simulated delay has begun).
    func waitUntilSignInStarted() async {
        if hasSignInStarted { return }
        await withCheckedContinuation { continuation in
            if hasSignInStarted {
                continuation.resume()
            } else {
                signInStartedContinuations.append(continuation)
            }
        }
    }

    /// Builds a mock configured from process launch arguments for UI tests.
    static func makeForCurrentProcess() -> MockAuthenticationService {
        let arguments = ProcessInfo.processInfo.arguments
        var configuration = Configuration.default

        if arguments.contains("-UITesting") {
            configuration.simulatedDelayNanoseconds = 0
        }

        if arguments.contains("-UITestSignedIn") {
            configuration.initialSession = .mockAppleUser
        }

        if arguments.contains("-UITestSignInFails") {
            configuration.signInOutcome = .failure
        }

        if arguments.contains("-UITestSignInCancelled") {
            configuration.signInOutcome = .cancelled
        }

        if arguments.contains("-UITestAppleSystemError") {
            configuration.signInOutcome = .appleSystemError
        }

        if arguments.contains("-UITestInvalidCredential") {
            configuration.signInOutcome = .invalidCredential
        }

        if arguments.contains("-UITestNetworkError") {
            configuration.signInOutcome = .networkError
        }

        if arguments.contains("-UITestRestoreFails") {
            configuration.restoreFails = true
        }

        return MockAuthenticationService(configuration: configuration)
    }

    func restoreSession() async throws -> AuthenticationSession? {
        try await simulateDelay()

        if configuration.restoreFails {
            throw AuthenticationError.unavailable
        }

        return session
    }

    func signIn(with provider: AuthenticationProvider) async throws -> AuthenticationSession {
        signalSignInStarted()
        try await simulateDelay()

        switch configuration.signInOutcome {
        case .cancelled:
            throw AuthenticationError.cancelled
        case .appleSystemError:
            throw AuthenticationError.appleSystemError
        case .invalidCredential:
            throw AuthenticationError.invalidCredential
        case .networkError:
            throw AuthenticationError.networkError
        case .failure:
            throw AuthenticationError.unknown
        case .success:
            let session = AuthenticationSession.mock(for: provider)
            self.session = session
            return session
        }
    }

    func signInWithApple(authorization: ASAuthorization, rawNonce: String) async throws -> AuthenticationSession {
        try await signIn(with: .apple)
    }

    func signOut() async throws {
        try await simulateDelay()
        session = nil
    }

    func storePublicUserId(_ publicUserId: String) async throws {
        guard let session else { return }
        let user = session.user
        self.session = AuthenticationSession(
            user: AuthenticatedUser(
                id: user.id,
                displayName: user.displayName,
                email: user.email,
                publicUserId: publicUserId
            ),
            provider: session.provider
        )
    }

    private func simulateDelay() async throws {
        let delay = configuration.simulatedDelayNanoseconds
        guard delay > 0 else { return }
        try await Task.sleep(nanoseconds: delay)
    }

    private func signalSignInStarted() {
        hasSignInStarted = true
        let continuations = signInStartedContinuations
        signInStartedContinuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }
}

extension AuthenticationSession {
    static let mockAppleUser = AuthenticationSession(
        user: AuthenticatedUser(
            id: "mock-user-apple",
            displayName: "Mock Apple User",
            email: "mock.user@example.com",
            publicUserId: "APPLEUSER1"
        ),
        provider: .apple
    )

    static func mock(for provider: AuthenticationProvider) -> AuthenticationSession {
        switch provider {
        case .apple:
            return .mockAppleUser
        case .google:
            return AuthenticationSession(
                user: AuthenticatedUser(
                    id: "mock-user-google",
                    displayName: "Mock Google User",
                    email: "mock.google@example.com",
                    publicUserId: "GOOGLEUSR1"
                ),
                provider: .google
            )
        case .facebook:
            return AuthenticationSession(
                user: AuthenticatedUser(
                    id: "mock-user-facebook",
                    displayName: "Mock Facebook User",
                    email: "mock.facebook@example.com",
                    publicUserId: "FACEBKUSR1"
                ),
                provider: .facebook
            )
        }
    }
}
