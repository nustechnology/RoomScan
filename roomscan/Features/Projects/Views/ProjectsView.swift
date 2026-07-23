//
//  ProjectsView.swift
//  roomscan
//

import SwiftUI

struct ProjectsView: View {
    @State var viewModel: ProjectsViewModel
    var showsNavigationTitle = true

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                content

                if viewModel.showsPaginationError {
                    PaginationErrorToast {
                        Task {
                            await viewModel.retryPagination()
                        }
                    }
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle(showsNavigationTitle ? String(localized: "projects.title") : "")
            .toolbar(showsNavigationTitle ? .visible : .hidden, for: .navigationBar)
            .task {
                await viewModel.loadInitialProjects()
            }
            .animation(.default, value: viewModel.showsPaginationError)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.viewState {
        case .idle, .loading:
            ProgressView(String(localized: "projects.loading"))
                .accessibilityIdentifier("projects.loading")

        case .empty:
            ContentUnavailableView(String(localized: "projects.empty.message"), systemImage: "folder")
                .accessibilityIdentifier("projects.emptyState")

        case .failed:
            ContentUnavailableView(String(localized: "projects.load.error"), systemImage: "wifi.exclamationmark")
                .accessibilityIdentifier("projects.loadError")

        case .loaded:
            ScrollView {
                LazyVStack(spacing: 14) {
                    if viewModel.isRefreshing {
                        RefreshingBannerView()
                    }

                    ProjectsControlsView()

                    ForEach(viewModel.projects) { project in
                        ProjectCardView(
                            project: project,
                            visibleRoomScans: viewModel.visibleRoomScans(for: project),
                            isExpanded: viewModel.isExpanded(project.id),
                            showsExpandControl: viewModel.showsExpandControl(for: project),
                            onToggleExpansion: {
                                viewModel.toggleExpansion(for: project.id)
                            },
                            onRoomTap: {}
                        )
                        .onAppear {
                            Task {
                                await viewModel.loadNextPageIfNeeded(currentProjectID: project.id)
                            }
                        }
                    }

                    if viewModel.isLoadingNextPage {
                        LoadingMoreFooterView()
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 24)
            }
            .refreshable {
                await viewModel.refreshProjects()
            }
            .accessibilityIdentifier("projects.list")
        }
    }
}

private struct RefreshingBannerView: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text("projects.refreshing")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("projects.refreshing")
    }
}

private struct LoadingMoreFooterView: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text("projects.loadingMore")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.quaternary.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.top, 4)
        .accessibilityIdentifier("projects.loadingMore")
    }
}

private struct ProjectsControlsView: View {
    var body: some View {
        VStack(spacing: 16) {
            SearchPlaceholderView()

            PrimaryActionButton(
                title: String(localized: "home.newScan"),
                systemImageName: "plus",
                color: .blue,
                action: {},
                accessibilityIdentifier: "home.newScan"
            )
            .padding(.bottom, 6)
        }
    }
}

private struct SearchPlaceholderView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("home.search.placeholder")
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(.quaternary.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(String(localized: "home.search.placeholder"))
        .accessibilityIdentifier("home.search")
    }
}

private struct PaginationErrorToast: View {
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("projects.pagination.error")
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(2)

            Spacer()

            Button(String(localized: "projects.pagination.retry"), action: onRetry)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .accessibilityIdentifier("projects.pagination.retry")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.black.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("projects.pagination.toast")
    }
}

#Preview {
    ProjectsView(
        viewModel: ProjectsViewModel(
            service: MockProjectsService(simulatedDelayNanoseconds: 0)
        )
    )
}
