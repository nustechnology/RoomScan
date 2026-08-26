//
//  AccountView.swift
//  roomscan
//

import SwiftUI

struct AccountView: View {
    let session: AuthenticationSession
    let onSignOut: () -> Void

    @State private var viewModel: AccountViewModel

    init(
        session: AuthenticationSession,
        projectsService: any ProjectsService,
        sharedService: any SharedService,
        syncService: any SyncService,
        usersService: any UsersService,
        storageMeasuring: any AccountStorageMeasuring = MockAccountStorageMeasuring(),
        onUserUpdated: @escaping (AuthenticatedUser) -> Void = { _ in },
        onSignOut: @escaping () -> Void
    ) {
        self.session = session
        self.onSignOut = onSignOut
        _viewModel = State(
            initialValue: AccountViewModel(
                projectsService: projectsService,
                sharedService: sharedService,
                syncService: syncService,
                usersService: usersService,
                storageMeasuring: storageMeasuring,
                onUserUpdated: onUserUpdated
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.large) {
                AccountProfileCard(session: session) {
                    viewModel.openEditNameSheet(currentDisplayName: session.user.displayName)
                }

                if let metrics = viewModel.metrics {
                    if metrics.showsSyncPendingBanner {
                        AccountSyncPendingBanner(pendingCount: metrics.pendingSyncCount)
                    }

                    AccountMetricsList(metrics: metrics)

                    if viewModel.loadFailed {
                        AccountMetricsLoadFailureRow {
                            Task { await viewModel.loadMetrics() }
                        }
                    }
                } else if viewModel.loadFailed {
                    ContentUnavailableView {
                        Label(
                            String(localized: "account.metrics.load.error"),
                            systemImage: "wifi.exclamationmark"
                        )
                    } actions: {
                        Button(String(localized: "account.metrics.load.retry")) {
                            Task { await viewModel.loadMetrics() }
                        }
                        .accessibilityIdentifier("account.metrics.retry")
                    }
                    .accessibilityIdentifier("account.metrics.loadError")
                } else if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.doubleExtraLarge)
                        .accessibilityIdentifier("account.loading")
                }
            }
            .padding(.horizontal, AppSpacing.extraLarge)
            .padding(.top, AppSpacing.small)
            .padding(.bottom, AppSpacing.doubleExtraLarge)
        }
        .safeAreaInset(edge: .bottom) {
            signOutButton
                .padding(.horizontal, AppSpacing.extraLarge)
                .padding(.vertical, AppSpacing.small)
        }
        .background(AppColors.background)
        .task {
            async let profile: Void = viewModel.loadProfile(currentUser: session.user)
            async let metrics: Void = viewModel.loadMetrics()
            _ = await (profile, metrics)
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.isEditNameSheetPresented },
                set: { if !$0 { viewModel.closeEditNameSheet() } }
            )
        ) {
            EditDisplayNameBottomSheet(
                displayName: Binding(
                    get: { viewModel.editedDisplayName },
                    set: { viewModel.updateEditedDisplayName($0) }
                ),
                validationMessage: viewModel.editValidationMessage,
                errorMessage: viewModel.saveErrorMessage,
                isSaving: viewModel.isSavingDisplayName,
                canSave: viewModel.canSaveDisplayName,
                onSave: {
                    Task { await viewModel.saveDisplayName(currentUser: session.user) }
                }
            )
        }
        .alert(
            String(localized: "account.signOut.confirm.title"),
            isPresented: signOutConfirmationBinding
        ) {
            Button(String(localized: "account.signOut.confirm.cancel"), role: .cancel) {
                viewModel.dismissSignOutConfirmation()
            }
            Button(String(localized: "account.signOut"), role: .destructive) {
                viewModel.confirmSignOut(onSignOut: onSignOut)
            }
            .accessibilityIdentifier("account.signOut.confirm")
        } message: {
            Text("account.signOut.confirm.message")
        }
    }

    private var signOutButton: some View {
        Button {
            viewModel.requestSignOut()
        } label: {
            Text("account.signOut")
                .appTypography(AppTypography.headingSmall)
                .foregroundStyle(AppColors.destructiveLabel)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.large)
                .background(
                    RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous)
                        .fill(AppColors.destructiveSoftBackground)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("account.signOut")
    }

    private var signOutConfirmationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showsSignOutConfirmation },
            set: { isPresented in
                if isPresented {
                    viewModel.requestSignOut()
                } else {
                    viewModel.dismissSignOutConfirmation()
                }
            }
        )
    }
}

private struct AccountMetricsLoadFailureRow: View {
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(AppColors.secondaryText)
                .accessibilityHidden(true)

            Text("account.metrics.load.error")
                .appTypography(AppTypography.bodySmall)
                .foregroundStyle(AppColors.secondaryText)

            Spacer(minLength: AppSpacing.small)

            Button(String(localized: "account.metrics.load.retry"), action: onRetry)
                .accessibilityIdentifier("account.metrics.refreshRetry")
        }
        .padding(.vertical, AppSpacing.small)
        .accessibilityIdentifier("account.metrics.loadFailure")
    }
}

#Preview {
    AccountView(
        session: .mockAppleUser,
        projectsService: MockProjectsService(simulatedDelayNanoseconds: 0),
        sharedService: MockSharedService(simulatedDelayNanoseconds: 0),
        syncService: MockSyncService(simulatedDelayNanoseconds: 0),
        usersService: MockUsersService(),
        onSignOut: {}
    )
}
