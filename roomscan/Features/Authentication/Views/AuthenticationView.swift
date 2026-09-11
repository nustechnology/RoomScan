//
//  AuthenticationView.swift
//  roomscan
//

import AuthenticationServices
import SwiftUI
import UIKit

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
        let control = AppleAuthorizationButton(
            isEnabled: !viewModel.isSigningIn,
            prepareAttempt: {
                viewModel.prepareAppleSignInRequest()
            },
            hashNonce: { rawNonce in
                viewModel.sha256(rawNonce)
            },
            onSuccess: { authorization, attemptID in
                Task {
                    if let session = await viewModel.completeAppleSignIn(
                        authorization: authorization,
                        attemptID: attemptID
                    ) {
                        appState.applySignedInSession(session)
                    }
                }
            },
            onFailure: { error, attemptID in
                viewModel.handleAppleSignInError(error, attemptID: attemptID)
            }
        )
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

        Group {
            if isUITesting {
                control
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
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
        .overlay {
            if viewModel.isSigningIn {
                HStack(spacing: AppSpacing.small) {
                    ProgressView()
                        .controlSize(.large)
                        .scaleEffect(0.65)
                        .tint(.white)
                    Text("auth.signingIn")
                        .appTypography(AppTypography.labelButton)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: AppCornerRadius.medium,
                        style: .continuous
                    )
                )
                .allowsHitTesting(false)
                .accessibilityIdentifier("auth.signingIn")
            }
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

}

private struct AppleAuthorizationButton: UIViewRepresentable {
    private struct AuthorizationContext {
        let controller: ASAuthorizationController
        let attemptID: UUID
    }

    let isEnabled: Bool
    let prepareAttempt: () -> AuthenticationViewModel.AppleSignInAttempt
    let hashNonce: (String) -> String
    let onSuccess: (ASAuthorization, UUID) -> Void
    let onFailure: (Error, UUID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            prepareAttempt: prepareAttempt,
            hashNonce: hashNonce,
            onSuccess: onSuccess,
            onFailure: onFailure
        )
    }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: .black)
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.startAuthorization),
            for: .touchUpInside
        )
        context.coordinator.button = button
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        uiView.isEnabled = isEnabled
        context.coordinator.prepareAttempt = prepareAttempt
        context.coordinator.hashNonce = hashNonce
        context.coordinator.onSuccess = onSuccess
        context.coordinator.onFailure = onFailure
    }

    @MainActor
    final class Coordinator: NSObject,
        ASAuthorizationControllerDelegate,
        ASAuthorizationControllerPresentationContextProviding {
        weak var button: ASAuthorizationAppleIDButton?
        var prepareAttempt: () -> AuthenticationViewModel.AppleSignInAttempt
        var hashNonce: (String) -> String
        var onSuccess: (ASAuthorization, UUID) -> Void
        var onFailure: (Error, UUID) -> Void

        private var authorizationContexts: [ObjectIdentifier: AuthorizationContext] = [:]

        init(
            prepareAttempt: @escaping () -> AuthenticationViewModel.AppleSignInAttempt,
            hashNonce: @escaping (String) -> String,
            onSuccess: @escaping (ASAuthorization, UUID) -> Void,
            onFailure: @escaping (Error, UUID) -> Void
        ) {
            self.prepareAttempt = prepareAttempt
            self.hashNonce = hashNonce
            self.onSuccess = onSuccess
            self.onFailure = onFailure
        }

        @objc func startAuthorization() {
            let attempt = prepareAttempt()
            cancelAuthorizationContexts(except: attempt.id)
            guard !authorizationContexts.values.contains(where: { $0.attemptID == attempt.id }) else {
                return
            }

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = hashNonce(attempt.rawNonce)

            let controller = ASAuthorizationController(authorizationRequests: [request])
            let context = AuthorizationContext(controller: controller, attemptID: attempt.id)
            authorizationContexts[ObjectIdentifier(controller)] = context
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }

        func authorizationController(
            controller: ASAuthorizationController,
            didCompleteWithAuthorization authorization: ASAuthorization
        ) {
            guard let attemptID = finishAuthorization(for: controller) else { return }
            onSuccess(authorization, attemptID)
        }

        func authorizationController(
            controller: ASAuthorizationController,
            didCompleteWithError error: Error
        ) {
            guard let attemptID = finishAuthorization(for: controller) else { return }
            onFailure(error, attemptID)
        }

        func presentationAnchor(
            for controller: ASAuthorizationController
        ) -> ASPresentationAnchor {
            button?.window ?? ASPresentationAnchor()
        }

        private func finishAuthorization(for controller: ASAuthorizationController) -> UUID? {
            authorizationContexts
                .removeValue(forKey: ObjectIdentifier(controller))?
                .attemptID
        }

        private func cancelAuthorizationContexts(except attemptID: UUID) {
            let staleContexts = authorizationContexts.filter { $0.value.attemptID != attemptID }
            for (identifier, context) in staleContexts {
                authorizationContexts.removeValue(forKey: identifier)
                context.controller.cancel()
            }
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
