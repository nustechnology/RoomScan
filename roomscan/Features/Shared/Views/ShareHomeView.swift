//
//  ShareHomeView.swift
//  roomscan
//

import SwiftUI

struct ShareHomeView: View {
    @State var viewModel: ShareHomeViewModel
    let acceptedDestinations: [AcceptedInvitationDestination]
    let onOpen: (AcceptedInvitationDestination) -> Void

    init(
        viewModel: ShareHomeViewModel,
        acceptedDestinations: [AcceptedInvitationDestination],
        onOpen: @escaping (AcceptedInvitationDestination) -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.acceptedDestinations = acceptedDestinations
        self.onOpen = onOpen
    }

    private var destinations: [AcceptedInvitationDestination] {
        viewModel.destinations(merging: acceptedDestinations)
    }

    var body: some View {
        Group {
            switch contentState {
            case .loading:
                ProgressView(String(localized: "shared.loading"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("home.share.loading")

            case .failed:
                ContentUnavailableView {
                    Label(String(localized: "shared.load.error"), systemImage: "wifi.exclamationmark")
                } actions: {
                    Button(String(localized: "shared.load.retry")) {
                        Task { await viewModel.refresh() }
                    }
                    .accessibilityIdentifier("home.share.retry")
                }
                .accessibilityIdentifier("home.share.error")

            case .empty:
                ContentUnavailableView {
                    Label(
                        String(localized: "home.share.title"),
                        systemImage: "square.and.arrow.up"
                    )
                } description: {
                    Text("home.share.placeholder")
                } actions: {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.body.weight(.semibold))
                            .frame(width: 54, height: 54)
                    }
                    .accessibilityLabel(String(localized: "shared.refresh.accessibility"))
                }

            case .loaded:
                ScrollView {
                    LazyVStack(spacing: AppSpacing.medium) {
                        ForEach(destinations) { destination in
                            Button {
                                onOpen(destination)
                            } label: {
                                SharedInvitationRow(destination: destination)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("home.share.item.\(destination.id)")
                        }
                    }
                    .padding(.horizontal, AppSpacing.extraLarge)
                    .padding(.vertical, AppSpacing.large)
                }
                .refreshable {
                    await viewModel.refresh()
                }
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .accessibilityIdentifier("home.share")
    }

    private var contentState: ContentState {
        if !destinations.isEmpty {
            return .loaded
        }

        switch viewModel.viewState {
        case .idle, .loading:
            return .loading
        case .failed:
            return .failed
        case .empty, .loaded:
            return .empty
        }
    }

    private enum ContentState {
        case loading
        case failed
        case empty
        case loaded
    }
}

private struct SharedInvitationRow: View {
    let destination: AcceptedInvitationDestination

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            Image(systemName: systemImageName)
                .font(.title2)
                .foregroundStyle(AppColors.brandPrimary)
                .frame(width: 44, height: 44)
                .background(AppColors.brandPrimary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppSpacing.extraSmall) {
                Text(title)
                    .appTypography(AppTypography.bodyMediumStrong)
                    .foregroundStyle(AppColors.primaryText)
                    .lineLimit(2)

                Text(kindLabel)
                    .appTypography(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.secondaryText)
            }

            Spacer(minLength: AppSpacing.small)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppColors.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(AppSpacing.medium)
        .background(AppColors.background)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                .stroke(AppColors.borderDefault, lineWidth: 1)
        }
    }

    private var title: String {
        switch destination {
        case .project(let project):
            return project.name
        case .scan(let input):
            return input.scanName
        }
    }

    private var kindLabel: String {
        switch destination {
        case .project:
            return String(localized: "invitation.project.title")
        case .scan:
            return String(localized: "invitation.scan.title")
        }
    }

    private var systemImageName: String {
        switch destination {
        case .project:
            return "folder"
        case .scan:
            return "cube"
        }
    }
}

#Preview {
    ShareHomeView(
        viewModel: ShareHomeViewModel(
            service: MockSharedService(simulatedDelayNanoseconds: 0)
        ),
        acceptedDestinations: [],
        onOpen: { _ in }
    )
}
