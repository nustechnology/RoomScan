//
//  AuthenticationViewModel.swift
//  roomscan
//

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
            if error == .cancelled {
                viewState = .idle
            } else {
                viewState = .failed(error)
            }
            return nil
        } catch {
            viewState = .failed(.unknown)
            return nil
        }
    }

    func dismissError() {
        viewState = .idle
    }

    @discardableResult
    func retrySignIn() async -> AuthenticationSession? {
        await signInWithApple()
    }
}
