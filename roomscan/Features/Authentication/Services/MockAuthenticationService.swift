//
//  MockAuthenticationService.swift
//  roomscan
//

import Foundation

/// Deterministic in-memory authentication used for development, previews, and tests.
/// Not a production Sign in with Apple implementation.
@MainActor
final class MockAuthenticationService: AuthenticationService {
    enum SignInOutcome: Equatable, Sendable {
        case success
        case cancelled
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

    init(configuration: Configuration = .default) {
        self.configuration = configuration
        self.session = configuration.initialSession
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
        try await simulateDelay()

        switch configuration.signInOutcome {
        case .cancelled:
            throw AuthenticationError.cancelled
        case .failure:
            throw AuthenticationError.unknown
        case .success:
            let session = AuthenticationSession.mock(for: provider)
            self.session = session
            return session
        }
    }

    func signOut() async throws {
        try await simulateDelay()
        session = nil
    }

    private func simulateDelay() async throws {
        let delay = configuration.simulatedDelayNanoseconds
        guard delay > 0 else { return }
        try await Task.sleep(nanoseconds: delay)
    }
}

extension AuthenticationSession {
    static let mockAppleUser = AuthenticationSession(
        user: AuthenticatedUser(
            id: "mock-user-apple",
            displayName: "Mock Apple User",
            email: "mock.user@example.com"
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
                    email: "mock.google@example.com"
                ),
                provider: .google
            )
        case .facebook:
            return AuthenticationSession(
                user: AuthenticatedUser(
                    id: "mock-user-facebook",
                    displayName: "Mock Facebook User",
                    email: "mock.facebook@example.com"
                ),
                provider: .facebook
            )
        }
    }
}
