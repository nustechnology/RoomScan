//
//  AuthenticationViewModelTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

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

    @Test func preparingAppleRequestImmediatelyShowsLoadingAndReusesNonce() {
        let service = MockAuthenticationService()
        let viewModel = AuthenticationViewModel(authenticationService: service)

        let firstNonce = viewModel.prepareAppleSignInRequest()
        let repeatedNonce = viewModel.prepareAppleSignInRequest()

        #expect(!firstNonce.rawNonce.isEmpty)
        #expect(repeatedNonce == firstNonce)
        #expect(viewModel.viewState == .signingIn)
        #expect(viewModel.isSigningIn)
    }

    @Test func appleRequestTimeoutShowsRetryableError() async {
        let service = MockAuthenticationService()
        let viewModel = AuthenticationViewModel(
            authenticationService: service,
            appleAuthorizationTimeoutNanoseconds: 1_000_000
        )

        _ = viewModel.prepareAppleSignInRequest()
        await waitUntilAppleSignInFinishes(viewModel)

        #expect(viewModel.viewState == .failed(.appleSystemError))
        #expect(!viewModel.isSigningIn)
        #expect(viewModel.toastMessage == AuthenticationError.appleSystemError.errorDescription)
        #expect(viewModel.toastStyle == .error)
    }

    @Test func lateFailureDoesNotClearRetriedAppleRequest() async {
        let service = MockAuthenticationService()
        let viewModel = AuthenticationViewModel(
            authenticationService: service,
            appleAuthorizationTimeoutNanoseconds: 1_000_000
        )
        let expiredAttempt = viewModel.prepareAppleSignInRequest()
        await waitUntilAppleSignInFinishes(viewModel)
        #expect(!viewModel.isSigningIn)
        let retryAttempt = viewModel.prepareAppleSignInRequest()

        viewModel.handleAppleSignInError(
            AuthenticationError.appleSystemError,
            attemptID: expiredAttempt.id
        )

        #expect(viewModel.isSigningIn)
        #expect(viewModel.prepareAppleSignInRequest() == retryAttempt)
    }

    @Test func lateSuccessDoesNotAuthenticateOrClearRetriedAppleRequest() async {
        let service = MockAuthenticationService()
        let viewModel = AuthenticationViewModel(
            authenticationService: service,
            appleAuthorizationTimeoutNanoseconds: 1_000_000
        )
        let expiredAttempt = viewModel.prepareAppleSignInRequest()
        await waitUntilAppleSignInFinishes(viewModel)
        #expect(!viewModel.isSigningIn)
        let retryAttempt = viewModel.prepareAppleSignInRequest()
        var didAuthenticate = false

        let session = await viewModel.completeAppleSignIn(attemptID: expiredAttempt.id) { _ in
            didAuthenticate = true
            return .mockAppleUser
        }

        #expect(session == nil)
        #expect(!didAuthenticate)
        #expect(viewModel.isSigningIn)
        #expect(viewModel.prepareAppleSignInRequest() == retryAttempt)
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
        #expect(viewModel.toastStyle == .error)
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
        #expect(viewModel.toastStyle == .error)
    }

    private func waitUntilAppleSignInFinishes(_ viewModel: AuthenticationViewModel) async {
        let deadline = Date().addingTimeInterval(1)
        while viewModel.isSigningIn, Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
            await Task.yield()
        }
    }
}
