//
//  HomeBottomNav.swift
//  roomscan
//

import SwiftUI

struct HomeBottomNav: View {
    @Binding var selectedTab: HomeView.Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HomeView.Tab.allCases, id: \.self) { tab in
                Button(
                    action: {
                        selectedTab = tab
                    },
                    label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.systemImageName(isSelected: selectedTab == tab))
                                .font(.system(size: 21, weight: .semibold))

                            Text(tab.localizedTitle)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(selectedTab == tab ? .blue : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .contentShape(Rectangle())
                    }
                )
                .buttonStyle(.plain)
                .accessibilityLabel(tab.localizedTitle)
                .accessibilityIdentifier(tab.accessibilityIdentifier)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.quaternary)
                .frame(height: 1)
        }
    }
}

extension HomeView.Tab {
    var headerTitle: String {
        switch self {
        case .projects:
            return String(localized: "projects.title")
        case .share:
            return String(localized: "home.share.headerTitle")
        case .account:
            return String(localized: "account.title")
        }
    }

    var localizedTitle: String {
        switch self {
        case .projects:
            return String(localized: "projects.nav.project")
        case .share:
            return String(localized: "home.share.nav")
        case .account:
            return String(localized: "account.title")
        }
    }

    func systemImageName(isSelected: Bool) -> String {
        switch self {
        case .projects:
            return isSelected ? "square.grid.2x2.fill" : "square.grid.2x2"
        case .share:
            return "point.3.filled.connected.trianglepath.dotted"
        case .account:
            return isSelected ? "person.fill" : "person"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .projects:
            return "tab.projects"
        case .share:
            return "tab.share"
        case .account:
            return "tab.account"
        }
    }
}
