//
//  AuthenticationView.swift
//  roomscan
//

import SwiftUI

struct AuthenticationView: View {
    @Bindable var appState: AppState
    @State private var viewModel: AuthenticationViewModel
    @State private var path = NavigationPath()

    init(appState: AppState) {
        self.appState = appState
        _viewModel = State(
            initialValue: AuthenticationViewModel(
                authenticationService: appState.authenticationService
            )
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "viewfinder.rectangular")
                    .font(.system(size: 56))
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text("auth.title")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("auth.title")

                    Text("auth.subtitle")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("auth.subtitle")
                }

                Spacer()

                VStack(spacing: 16) {
                    Button {
                        Task {
                            if let session = await viewModel.signInWithApple() {
                                appState.applySignedInSession(session)
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "apple.logo")
                            Text("auth.continueWithApple")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.primary)
                    .foregroundStyle(.background)
                    .disabled(viewModel.isSigningIn)
                    .accessibilityIdentifier("auth.signInWithApple")
                    .accessibilityLabel(Text("auth.continueWithApple"))

                    if viewModel.isSigningIn {
                        ProgressView(String(localized: "auth.signingIn"))
                            .accessibilityIdentifier("auth.signingIn")
                    }

                    if let errorMessage = viewModel.errorMessage {
                        VStack(spacing: 8) {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .accessibilityIdentifier("auth.error")

                            Button("auth.retry") {
                                Task {
                                    if let session = await viewModel.retrySignIn() {
                                        appState.applySignedInSession(session)
                                    }
                                }
                            }
                            .accessibilityIdentifier("auth.retry")
                        }
                    }

                    HStack(spacing: 16) {
                        Button("auth.privacy") {
                            path.append(AppRoute.privacyPolicy)
                        }
                        .accessibilityIdentifier("auth.privacy")

                        Button("auth.terms") {
                            path.append(AppRoute.termsOfService)
                        }
                        .accessibilityIdentifier("auth.terms")
                    }
                    .font(.footnote)
                }
            }
            .padding(24)
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .privacyPolicy:
                    LegalDocumentView(
                        titleKey: "auth.privacy.title",
                        bodyKey: "auth.privacy.body"
                    )
                case .termsOfService:
                    LegalDocumentView(
                        titleKey: "auth.terms.title",
                        bodyKey: "auth.terms.body"
                    )
                }
            }
        }
    }
}

#Preview("Signed out") {
    AuthenticationView(
        appState: AppState(authenticationService: MockAuthenticationService())
    )
}
