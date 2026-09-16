//
//  HomeHeader.swift
//  roomscan
//

import SwiftUI

struct HomeHeader: View {
    let title: String
    let showsCreateProjectButton: Bool
    let showsRefreshButton: Bool
    let onCreateProject: () -> Void
    var onRefresh: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.largeTitle.bold())
                .lineLimit(1)
                .accessibilityIdentifier("home.header.title")

            if showsCreateProjectButton {
                Button(action: onCreateProject) {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "projects.create.accessibility"))
                .accessibilityIdentifier("projects.create")
            }

            Spacer()

            if showsRefreshButton {
                Button(
                    action: { onRefresh?() },
                    label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                )
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "shared.refresh.accessibility"))
                .accessibilityIdentifier("shared.refresh")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 2)
        .padding(.bottom, 4)
        .background(.background)
    }
}
