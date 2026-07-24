//
//  AuthenticationViewModelTests.swift
//  roomscanTests
//

import Foundation
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

    @Test func signInWithAppleExposesSigningInStateWhileInProgress() async {
        let service = MockAuthenticationService(
            configuration: .init(
                initialSession: nil,
                signInOutcome: .success,
                restoreFails: false,
                simulatedDelayNanoseconds: 50_000_000
            )
        )
        let viewModel = AuthenticationViewModel(authenticationService: service)

        async let session = viewModel.signInWithApple()
        await service.waitUntilSignInStarted()

        #expect(viewModel.viewState == .signingIn)
        #expect(viewModel.isSigningIn)

        #expect(await session == .mockAppleUser)
        #expect(viewModel.viewState == .idle)
    }

    @Test func signInWithAppleIgnoresReentrancyWhileSigningIn() async {
        let service = MockAuthenticationService(
            configuration: .init(
                initialSession: nil,
                signInOutcome: .success,
                restoreFails: false,
                simulatedDelayNanoseconds: 50_000_000
            )
        )
        let viewModel = AuthenticationViewModel(authenticationService: service)

        async let firstSession = viewModel.signInWithApple()
        await service.waitUntilSignInStarted()
        #expect(viewModel.isSigningIn)

        let secondSession = await viewModel.signInWithApple()

        #expect(secondSession == nil)
        #expect(await firstSession == .mockAppleUser)
        #expect(viewModel.viewState == .idle)
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
        #expect(viewModel.errorMessage == AuthenticationError.unknown.localizedDescription)
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
        #expect(viewModel.toastMessage == nil)
    }

    @Test func networkErrorExposesNetworkToastMessage() async {
        let service = MockAuthenticationService(
            configuration: .init(
                initialSession: nil,
                signInOutcome: .networkError,
                restoreFails: false,
                simulatedDelayNanoseconds: 0
            )
        )
        let viewModel = AuthenticationViewModel(authenticationService: service)

        let session = await viewModel.signInWithApple()

        #expect(session == nil)
        #expect(viewModel.viewState == .failed(.networkError))
        #expect(viewModel.toastMessage == AuthenticationError.networkError.errorDescription)
    }

    @Test func invalidCredentialErrorExposesCredentialToastMessage() async {
        let service = MockAuthenticationService(
            configuration: .init(
                initialSession: nil,
                signInOutcome: .invalidCredential,
                restoreFails: false,
                simulatedDelayNanoseconds: 0
            )
        )
        let viewModel = AuthenticationViewModel(authenticationService: service)

        let session = await viewModel.signInWithApple()

        #expect(session == nil)
        #expect(viewModel.viewState == .failed(.invalidCredential))
        #expect(viewModel.toastMessage == AuthenticationError.invalidCredential.errorDescription)
    }
}
