//
//  AuthenticationViewModelTests.swift
//  roomscanTests
//

import Testing
@testable import roomscan

@MainActor
struct AuthenticationViewModelTests {
    @Test func signInWithAppleSucceedsAndReturnsSession() async {
        let service = MockAuthenticationService(
            configuration: .init(
                initialSession: nil,
                signInOutcome: .success,
                restoreFails: false,
                simulatedDelayNanoseconds: 0
            )
        )
        let viewModel = AuthenticationViewModel(authenticationService: service)

        let session = await viewModel.signInWithApple()

        #expect(viewModel.viewState == .idle)
        #expect(session == .mockAppleUser)
    }

    @Test func signInWithAppleCancellationKeepsIdleState() async {
        let service = MockAuthenticationService(
            configuration: .init(
                initialSession: nil,
                signInOutcome: .cancelled,
                restoreFails: false,
                simulatedDelayNanoseconds: 0
            )
        )
        let viewModel = AuthenticationViewModel(authenticationService: service)

        let session = await viewModel.signInWithApple()

        #expect(viewModel.viewState == .idle)
        #expect(session == nil)
    }

    @Test func signInWithAppleFailureExposesRetryableError() async {
        let service = MockAuthenticationService(
            configuration: .init(
                initialSession: nil,
                signInOutcome: .failure,
                restoreFails: false,
                simulatedDelayNanoseconds: 0
            )
        )
        let viewModel = AuthenticationViewModel(authenticationService: service)

        let session = await viewModel.signInWithApple()

        #expect(viewModel.viewState == .failed(.unknown))
        #expect(viewModel.errorMessage != nil)
        #expect(session == nil)
    }

    @Test func dismissErrorReturnsToIdle() async {
        let service = MockAuthenticationService(
            configuration: .init(
                initialSession: nil,
                signInOutcome: .failure,
                restoreFails: false,
                simulatedDelayNanoseconds: 0
            )
        )
        let viewModel = AuthenticationViewModel(authenticationService: service)
        _ = await viewModel.signInWithApple()

        viewModel.dismissError()

        #expect(viewModel.viewState == .idle)
    }
}
