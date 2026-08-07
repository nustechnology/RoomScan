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
    @State private var currentRawNonce: String?

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
        .toast(message: $viewModel.toastMessage, style: $viewModel.toastStyle)
        .onAppear {
            if let pendingToast = appState.consumePendingToastMessage() {
                viewModel.toastMessage = pendingToast
                viewModel.toastStyle = .success
            }
        }
        .preferredColorScheme(.light)
    }

    private var legalLinks: some View {
        Text(legalAttributedText)
            .appTypography(AppTypography.captionMedium)
            .foregroundStyle(AppColors.secondaryText)
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("auth.legal")
            .environment(\.openURL, OpenURLAction { url in
                switch url.absoluteString {
                case AuthenticationLegalLink.privacyURL.absoluteString:
                    path.append(AppRoute.privacyPolicy)
                    return .handled
                case AuthenticationLegalLink.termsURL.absoluteString:
                    path.append(AppRoute.termsOfService)
                    return .handled
                default:
                    return .systemAction
                }
            })
        .padding(.top, AppSpacing.medium)
    }

    private var legalAttributedText: AttributedString {
        let privacyTitle = String(localized: "auth.privacy.title")
        let termsTitle = String(localized: "auth.terms.title")
        let markdown = String.localizedStringWithFormat(
            String(localized: "auth.legal.markdown"),
            privacyTitle,
            AuthenticationLegalLink.privacyURL.absoluteString,
            termsTitle,
            AuthenticationLegalLink.termsURL.absoluteString
        )

        if let attributed = try? AttributedString(markdown: markdown) {
            return attributed
        }

        var fallback = AttributedString("By continuing, you agree to the ")

        var privacyLink = AttributedString(privacyTitle)
        privacyLink.link = AuthenticationLegalLink.privacyURL
        fallback.append(privacyLink)

        fallback.append(AttributedString(" and "))

        var termsLink = AttributedString(termsTitle)
        termsLink.link = AuthenticationLegalLink.termsURL
        fallback.append(termsLink)

        return fallback
    }

    @ViewBuilder
    private var signInButton: some View {
        let control = SignInWithAppleButton(.signIn) { request in
            let rawNonce = viewModel.generateRawNonce()
            currentRawNonce = rawNonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = viewModel.sha256(rawNonce)
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                guard let rawNonce = currentRawNonce else { return }
                Task {
                    if let session = await viewModel.signInWithApple(authorization: authorization, rawNonce: rawNonce) {
                        appState.applySignedInSession(session)
                    }
                }
            case .failure(let error):
                viewModel.handleAppleSignInError(error)
            }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(maxWidth: AuthenticationMetrics.maximumButtonWidth)
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
    static let maximumButtonWidth: CGFloat = 375
    static let disabledOpacity = 0.6
    static let minimumHitTarget: CGFloat = 44

    static let logoSize: CGFloat = 82
    static let logoShadowRadius: CGFloat = 12
    static let logoShadowY: CGFloat = 8
}

private enum AuthenticationLegalLink {
    static let privacyURL = URL(string: "roomscan-auth://privacy")!
    static let termsURL = URL(string: "roomscan-auth://terms")!
}

#Preview("Signed out") {
    AuthenticationView(
        appState: AppState(authenticationService: MockAuthenticationService())
    )
}
