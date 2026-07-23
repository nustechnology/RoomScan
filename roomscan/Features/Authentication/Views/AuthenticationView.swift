//
//  AuthenticationView.swift
//  roomscan
//

import AuthenticationServices
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
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        RoomScanLogo()

                        Text("auth.title")
                            .appTypography(AppTypography.headingLarge)
                            .foregroundStyle(AppColors.primaryText)
                            .multilineTextAlignment(.center)
                            .padding(.top, AppSpacing.extraLarge)
                            .accessibilityIdentifier("auth.title")

                        Text("auth.subtitle")
                            .appTypography(AppTypography.bodyLarge)
                            .foregroundStyle(AppColors.secondaryText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: AuthenticationMetrics.subtitleMaximumWidth)
                            .padding(.top, AppSpacing.medium)
                            .accessibilityIdentifier("auth.subtitle")

                        Spacer(minLength: AuthenticationMetrics.minimumContentSpacing)

                        VStack(spacing: 0) {
                            signInButton
                            statusContent
                            legalLinks
                        }
                    }
                    .padding(.horizontal, AppSpacing.extraLarge)
                    .padding(.top, AuthenticationMetrics.topInset)
                    .padding(.bottom, AppSpacing.doubleExtraLarge)
                    .frame(
                        minHeight: geometry.size.height,
                        alignment: .top
                    )
                }
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .privacyPolicy:
                    Text("auth.privacy.title")
                        .navigationTitle(String(localized: "auth.privacy.title"))
                case .termsOfService:
                    Text("auth.terms.title")
                        .navigationTitle(String(localized: "auth.terms.title"))
                }
            }
        }
    }

    private var legalLinks: some View {
        VStack(spacing: AppSpacing.extraSmall) {
            Text("auth.legal")
                .appTypography(AppTypography.captionMedium)
                .foregroundStyle(AppColors.secondaryText)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("auth.legal")

            NavigationLink(value: AppRoute.privacyPolicy) {
                Text("auth.privacy.title")
                    .appTypography(AppTypography.captionMediumStrong)
            }
            .accessibilityIdentifier("auth.privacy")

            NavigationLink(value: AppRoute.termsOfService) {
                Text("auth.terms.title")
                    .appTypography(AppTypography.captionMediumStrong)
            }
            .accessibilityIdentifier("auth.terms")
        }
        .padding(.top, AppSpacing.medium)
    }

    @ViewBuilder
    private var signInButton: some View {
        let control = SignInWithAppleButton(.signIn) { _ in
        } onCompletion: { result in
            if case .failure(let error) = result,
               let authorizationError = error as? ASAuthorizationError,
               authorizationError.code == .canceled {
                return
            }

            Task {
                await applySignInWithApple()
            }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(maxWidth: .infinity)
        .frame(height: AuthenticationMetrics.actionHeight)
        .clipShape(
            RoundedRectangle(
                cornerRadius: AppCornerRadius.medium,
                style: .continuous
            )
        )
        .disabled(viewModel.isSigningIn)
        .opacity(viewModel.isSigningIn ? AuthenticationMetrics.disabledOpacity : 1)

        if isUITesting {
            control
                .allowsHitTesting(false)
                .overlay {
                    Button {
                        Task {
                            await applySignInWithApple()
                        }
                    } label: {
                        Color.clear
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSigningIn)
                    .accessibilityIdentifier("auth.signInWithApple")
                }
        } else {
            control
                .accessibilityIdentifier("auth.signInWithApple")
        }
    }

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITesting")
    }

    private func applySignInWithApple() async {
        if let session = await viewModel.signInWithApple() {
            appState.applySignedInSession(session)
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        if viewModel.isSigningIn {
            ProgressView(String(localized: "auth.signingIn"))
                .appTypography(AppTypography.captionMedium)
                .padding(.top, AppSpacing.large)
                .accessibilityIdentifier("auth.signingIn")
        }

        if let errorMessage = viewModel.errorMessage {
            VStack(spacing: AppSpacing.small) {
                Text(errorMessage)
                    .appTypography(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.error)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("auth.error")

                Button("auth.retry") {
                    Task {
                        if let session = await viewModel.retrySignIn() {
                            appState.applySignedInSession(session)
                        }
                    }
                }
                .appTypography(AppTypography.captionMediumStrong)
                .frame(
                    minWidth: AuthenticationMetrics.minimumHitTarget,
                    minHeight: AuthenticationMetrics.minimumHitTarget
                )
                .contentShape(Rectangle())
                .accessibilityIdentifier("auth.retry")
            }
            .padding(.top, AppSpacing.large)
        }
    }
}

private struct RoomScanLogo: View {
    var body: some View {
        Image("AppLogo")
            .resizable()
            .scaledToFit()
            .frame(
                width: AuthenticationMetrics.logoSize,
                height: AuthenticationMetrics.logoSize
            )
            .shadow(
                color: AppShadows.logoColor,
                radius: AuthenticationMetrics.logoShadowRadius,
                y: AuthenticationMetrics.logoShadowY
            )
            .accessibilityHidden(true)
    }
}

private enum AuthenticationMetrics {
    static let topInset: CGFloat = 100
    static let subtitleMaximumWidth: CGFloat = 310
    static let minimumContentSpacing: CGFloat = 40
    static let actionHeight: CGFloat = 56
    static let disabledOpacity = 0.6
    static let minimumHitTarget: CGFloat = 44

    static let logoSize: CGFloat = 82
    static let logoShadowRadius: CGFloat = 12
    static let logoShadowY: CGFloat = 8
}

#Preview("Signed out") {
    AuthenticationView(
        appState: AppState(authenticationService: MockAuthenticationService())
    )
}
