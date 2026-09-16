//
//  AuthenticationViewModelTests.swift
//  roomscanTests
//

import AuthenticationServices
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

    @Test func beginningAppleAuthorizationImmediatelyShowsLoading() {
        let viewModel = AuthenticationViewModel(authenticationService: MockAuthenticationService())

        let attempt = viewModel.beginAppleAuthorization()

        #expect(!attempt.rawNonce.isEmpty)
        #expect(viewModel.beginAppleAuthorization() == attempt)
        #expect(viewModel.isAppleAuthorizationInProgress)
        #expect(viewModel.isSigningIn)
        viewModel.endAppleAuthorization(attemptID: attempt.id)
    }

    @Test func endingAppleAuthorizationStopsLoading() {
        let viewModel = AuthenticationViewModel(authenticationService: MockAuthenticationService())
        let attempt = viewModel.beginAppleAuthorization()

        viewModel.endAppleAuthorization(attemptID: attempt.id)

        #expect(!viewModel.isAppleAuthorizationInProgress)
        #expect(!viewModel.isSigningIn)
    }

    @Test func appleAuthorizationFailureStopsLoading() {
        let viewModel = AuthenticationViewModel(authenticationService: MockAuthenticationService())
        let attempt = viewModel.beginAppleAuthorization()

        viewModel.handleAppleSignInError(
            AuthenticationError.appleSystemError,
            attemptID: attempt.id
        )

        #expect(!viewModel.isAppleAuthorizationInProgress)
        #expect(!viewModel.isSigningIn)
        #expect(viewModel.viewState == .failed(.appleSystemError))
    }

    @Test func appleAuthorizationStaysActiveUntilTimeout() {
        let viewModel = AuthenticationViewModel(
            authenticationService: MockAuthenticationService(),
            appleAuthorizationTimeoutNanoseconds: 10_000_000_000
        )
        let attempt = viewModel.beginAppleAuthorization()

        #expect(viewModel.isAppleAuthorizationInProgress)
        #expect(viewModel.isSigningIn)
        #expect(viewModel.viewState == .idle)
        #expect(viewModel.toastMessage == nil)
        #expect(viewModel.beginAppleAuthorization() == attempt)
        viewModel.endAppleAuthorization(attemptID: attempt.id)
    }

    @Test func appleAuthorizationTimeoutUnlocksRetryWithoutFailingTheSheet() async {
        let viewModel = AuthenticationViewModel(
            authenticationService: MockAuthenticationService(),
            appleAuthorizationTimeoutNanoseconds: 1_000_000
        )
        let attempt = viewModel.beginAppleAuthorization()
        await waitUntilAppleAuthorizationFinishes(viewModel)

        #expect(!viewModel.isAppleAuthorizationInProgress)
        #expect(!viewModel.isSigningIn)
        #expect(viewModel.viewState == .idle)
        #expect(viewModel.toastMessage == nil)

        let session = await viewModel.signInWithApple(attemptID: attempt.id) { rawNonce in
            #expect(rawNonce == attempt.rawNonce)
            return .mockAppleUser
        }

        #expect(session == .mockAppleUser)
        #expect(!viewModel.isAppleAuthorizationInProgress)
    }

    @Test func appleAuthorizationTimeoutAllowsANewAttempt() async {
        let retried = await retriedAppleAuthorization(
            timeoutNanoseconds: 1_000_000
        ) { viewModel, _ in
            await waitUntilAppleAuthorizationFinishes(viewModel)
        }

        #expect(retried.retryAttempt != retried.expiredAttempt)
        await expectStaleAppleSignInRejected(retried)
    }

    @Test func timedOutAppleAuthorizationExpiresAndRejectsLateSignIn() async {
        let viewModel = AuthenticationViewModel(
            authenticationService: MockAuthenticationService(),
            appleAuthorizationTimeoutNanoseconds: 1_000_000,
            appleAuthorizationExpiryNanoseconds: 1_000_000
        )
        let attempt = viewModel.beginAppleAuthorization()
        await waitUntilAppleAuthorizationFinishes(viewModel)
        await waitForAppleAuthorizationGracePeriod()

        let session = await viewModel.signInWithApple(attemptID: attempt.id) { _ in .mockAppleUser }

        #expect(session == nil)
        #expect(viewModel.viewState == .failed(.appleSystemError))
        #expect(viewModel.toastMessage == AuthenticationError.appleSystemError.errorDescription)
    }

    @Test func expiredAppleAuthorizationDoesNotInterruptRetry() async {
        let retried = await retriedAppleAuthorization(
            timeoutNanoseconds: 1_000_000,
            expiryNanoseconds: 1_000_000
        ) { viewModel, _ in
            await waitUntilAppleAuthorizationFinishes(viewModel)
            await waitForAppleAuthorizationGracePeriod()
        }

        await expectStaleAppleSignInRejected(retried)
        #expect(
            retried.viewModel.toastMessage == AuthenticationError.appleSystemError.errorDescription
        )
    }

    @Test func timedOutAppleAuthorizationExpiresDuringUnrelatedExchange() async {
        let service = MockAuthenticationService(
            configuration: .init(
                initialSession: nil,
                signInOutcome: .success,
                restoreFails: false,
                simulatedDelayNanoseconds: 200_000_000
            )
        )
        let viewModel = AuthenticationViewModel(
            authenticationService: service,
            appleAuthorizationTimeoutNanoseconds: 1_000_000,
            appleAuthorizationExpiryNanoseconds: 20_000_000
        )
        let timedOutAttempt = viewModel.beginAppleAuthorization()
        await waitUntilAppleAuthorizationFinishes(viewModel)

        async let session = viewModel.signInWithApple()
        await service.waitUntilSignInStarted()
        await waitForAppleAuthorizationGracePeriod()

        #expect(await session == .mockAppleUser)
        var didAuthenticate = false
        let lateSession = await viewModel.signInWithApple(attemptID: timedOutAttempt.id) { _ in
            didAuthenticate = true
            return .mockAppleUser
        }

        #expect(lateSession == nil)
        #expect(!didAuthenticate)
        #expect(viewModel.toastMessage == AuthenticationError.appleSystemError.errorDescription)
    }

    @Test func expiredAppleAuthorizationDuringUnrelatedExchangeShowsError() async {
        let service = MockAuthenticationService(
            configuration: .init(
                initialSession: nil,
                signInOutcome: .success,
                restoreFails: false,
                simulatedDelayNanoseconds: 200_000_000
            )
        )
        let viewModel = AuthenticationViewModel(
            authenticationService: service,
            appleAuthorizationTimeoutNanoseconds: 1_000_000,
            appleAuthorizationExpiryNanoseconds: 1_000_000
        )
        let expiredAttempt = viewModel.beginAppleAuthorization()
        await waitUntilAppleAuthorizationFinishes(viewModel)
        await waitForAppleAuthorizationGracePeriod()

        async let session = viewModel.signInWithApple()
        await service.waitUntilSignInStarted()

        var didAuthenticate = false
        let lateSession = await viewModel.signInWithApple(attemptID: expiredAttempt.id) { _ in
            didAuthenticate = true
            return .mockAppleUser
        }

        #expect(lateSession == nil)
        #expect(!didAuthenticate)
        #expect(viewModel.toastMessage == AuthenticationError.appleSystemError.errorDescription)
        #expect(await session == .mockAppleUser)
        #expect(viewModel.toastMessage == AuthenticationError.appleSystemError.errorDescription)
    }

    @Test func timedOutAppleAuthorizationExchangeClaimsAttemptBeforeExpiry() async {
        let viewModel = AuthenticationViewModel(
            authenticationService: MockAuthenticationService(),
            appleAuthorizationTimeoutNanoseconds: 1_000_000,
            appleAuthorizationExpiryNanoseconds: 50_000_000
        )
        let attempt = viewModel.beginAppleAuthorization()
        await waitUntilAppleAuthorizationFinishes(viewModel)

        let session = await viewModel.signInWithApple(attemptID: attempt.id) { rawNonce in
            // Wait past the configured grace period. Claiming the attempt must have
            // cancelled expiry so this exchange still succeeds.
            try? await Task.sleep(nanoseconds: 100_000_000)
            for _ in 0..<5 {
                await Task.yield()
            }
            #expect(rawNonce == attempt.rawNonce)
            return .mockAppleUser
        }

        #expect(session == .mockAppleUser)
        #expect(viewModel.viewState == .idle)
        #expect(viewModel.toastMessage == nil)
        #expect(await viewModel.signInWithApple(attemptID: attempt.id) { _ in .mockAppleUser } == nil)
        #expect(viewModel.toastMessage == nil)
    }

    @Test func timedOutAppleAuthorizationFailureShowsError() async {
        let viewModel = AuthenticationViewModel(
            authenticationService: MockAuthenticationService(),
            appleAuthorizationTimeoutNanoseconds: 1_000_000
        )
        let attempt = viewModel.beginAppleAuthorization()
        await waitUntilAppleAuthorizationFinishes(viewModel)

        viewModel.handleAppleSignInError(ASAuthorizationError(.failed), attemptID: attempt.id)

        #expect(viewModel.viewState == .failed(.appleSystemError))
        #expect(viewModel.toastMessage == AuthenticationError.appleSystemError.errorDescription)
        #expect(await viewModel.signInWithApple(attemptID: attempt.id) { _ in .mockAppleUser } == nil)
    }

    @Test func firstAbandonedAppleAuthorizationFailureStillShowsErrorAfterTwoRetries() async {
        let viewModel = AuthenticationViewModel(
            authenticationService: MockAuthenticationService(),
            appleAuthorizationTimeoutNanoseconds: 1_000_000
        )
        let firstAttempt = viewModel.beginAppleAuthorization()
        await waitUntilAppleAuthorizationFinishes(viewModel)

        let secondAttempt = viewModel.beginAppleAuthorization()
        await waitUntilAppleAuthorizationFinishes(viewModel)

        let thirdAttempt = viewModel.beginAppleAuthorization()
        #expect(thirdAttempt.id != firstAttempt.id)
        #expect(thirdAttempt.id != secondAttempt.id)

        viewModel.handleAppleSignInError(ASAuthorizationError(.failed), attemptID: firstAttempt.id)

        #expect(viewModel.viewState == .failed(.appleSystemError))
        #expect(viewModel.toastMessage == AuthenticationError.appleSystemError.errorDescription)
        #expect(viewModel.isAppleAuthorizationInProgress)
        #expect(viewModel.beginAppleAuthorization() == thirdAttempt)
        viewModel.endAppleAuthorization(attemptID: thirdAttempt.id)
    }

    @Test func timedOutAppleAuthorizationCancellationStaysQuiet() async {
        let viewModel = AuthenticationViewModel(
            authenticationService: MockAuthenticationService(),
            appleAuthorizationTimeoutNanoseconds: 1_000_000
        )
        let attempt = viewModel.beginAppleAuthorization()
        await waitUntilAppleAuthorizationFinishes(viewModel)

        viewModel.handleAppleSignInError(ASAuthorizationError(.canceled), attemptID: attempt.id)

        #expect(viewModel.viewState == .idle)
        #expect(viewModel.toastMessage == nil)
        #expect(await viewModel.signInWithApple(attemptID: attempt.id) { _ in .mockAppleUser } == nil)
    }

    @Test func errorDuringCredentialExchangeDropsCompletableAttempt() async {
        let service = MockAuthenticationService(
            configuration: .init(
                initialSession: nil,
                signInOutcome: .success,
                restoreFails: false,
                simulatedDelayNanoseconds: 50_000_000
            )
        )
        let viewModel = AuthenticationViewModel(
            authenticationService: service,
            appleAuthorizationTimeoutNanoseconds: 1_000_000
        )
        let timedOutAttempt = viewModel.beginAppleAuthorization()
        await waitUntilAppleAuthorizationFinishes(viewModel)

        async let session = viewModel.signInWithApple()
        await service.waitUntilSignInStarted()
        viewModel.handleAppleSignInError(
            ASAuthorizationError(.failed),
            attemptID: timedOutAttempt.id
        )

        #expect(await session == .mockAppleUser)
        #expect(viewModel.toastMessage == nil)
        #expect(await viewModel.signInWithApple(attemptID: timedOutAttempt.id) { _ in .mockAppleUser } == nil)
    }

    @Test func sameAppleAuthorizationAttemptStillSignsIn() async {
        let viewModel = AuthenticationViewModel(authenticationService: MockAuthenticationService())
        let attempt = viewModel.beginAppleAuthorization()

        let session = await viewModel.signInWithApple(attemptID: attempt.id) { rawNonce in
            #expect(rawNonce == attempt.rawNonce)
            return .mockAppleUser
        }

        #expect(session == .mockAppleUser)
        #expect(viewModel.viewState == .idle)
        #expect(!viewModel.isAppleAuthorizationInProgress)
        #expect(viewModel.toastMessage == nil)
    }

    @Test func lateFailureDoesNotClearRetriedAppleAuthorization() {
        let viewModel = AuthenticationViewModel(authenticationService: MockAuthenticationService())
        let expiredAttempt = viewModel.beginAppleAuthorization()
        viewModel.endAppleAuthorization(attemptID: expiredAttempt.id)
        let retryAttempt = viewModel.beginAppleAuthorization()

        viewModel.handleAppleSignInError(
            AuthenticationError.appleSystemError,
            attemptID: expiredAttempt.id
        )

        #expect(viewModel.isAppleAuthorizationInProgress)
        #expect(viewModel.beginAppleAuthorization() == retryAttempt)
        viewModel.endAppleAuthorization(attemptID: retryAttempt.id)
    }

    @Test func lateSuccessDoesNotUseRetriedAppleAuthorizationNonce() async {
        let retried = await retriedAppleAuthorization { viewModel, attempt in
            viewModel.endAppleAuthorization(attemptID: attempt.id)
        }

        await expectStaleAppleSignInRejected(retried)
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

    private struct RetriedAppleAuthorization {
        let viewModel: AuthenticationViewModel
        let expiredAttempt: AuthenticationViewModel.AppleAuthorizationAttempt
        let retryAttempt: AuthenticationViewModel.AppleAuthorizationAttempt
    }

    private func retriedAppleAuthorization(
        timeoutNanoseconds: UInt64 = 120_000_000_000,
        expiryNanoseconds: UInt64 = 600_000_000_000,
        invalidate: (AuthenticationViewModel, AuthenticationViewModel.AppleAuthorizationAttempt) async -> Void
    ) async -> RetriedAppleAuthorization {
        let viewModel = AuthenticationViewModel(
            authenticationService: MockAuthenticationService(),
            appleAuthorizationTimeoutNanoseconds: timeoutNanoseconds,
            appleAuthorizationExpiryNanoseconds: expiryNanoseconds
        )
        let expiredAttempt = viewModel.beginAppleAuthorization()
        await invalidate(viewModel, expiredAttempt)
        return RetriedAppleAuthorization(
            viewModel: viewModel,
            expiredAttempt: expiredAttempt,
            retryAttempt: viewModel.beginAppleAuthorization()
        )
    }

    private func expectStaleAppleSignInRejected(_ retried: RetriedAppleAuthorization) async {
        var didAuthenticate = false
        let session = await retried.viewModel.signInWithApple(attemptID: retried.expiredAttempt.id) { _ in
            didAuthenticate = true
            return .mockAppleUser
        }

        #expect(session == nil)
        #expect(!didAuthenticate)
        #expect(
            retried.viewModel.toastMessage == AuthenticationError.appleSystemError.errorDescription
        )
        #expect(retried.viewModel.isAppleAuthorizationInProgress)
        #expect(retried.viewModel.beginAppleAuthorization() == retried.retryAttempt)
        retried.viewModel.endAppleAuthorization(attemptID: retried.retryAttempt.id)
    }

    /// Waits past a short grace-period timer, then yields so that timer's MainActor
    /// task can apply its result before the caller continues.
    private func waitForAppleAuthorizationGracePeriod() async {
        try? await Task.sleep(nanoseconds: 20_000_000)
        for _ in 0..<5 {
            await Task.yield()
        }
    }

    private func waitUntilAppleAuthorizationFinishes(_ viewModel: AuthenticationViewModel) async {
        let deadline = Date().addingTimeInterval(1)
        while viewModel.isAppleAuthorizationInProgress, Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
            await Task.yield()
        }
        if viewModel.isAppleAuthorizationInProgress {
            Issue.record("Apple authorization did not finish within 1s")
        }
    }
}
