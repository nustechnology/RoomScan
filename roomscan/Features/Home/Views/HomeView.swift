//
//  HomeView.swift
//  roomscan
//

import SwiftUI

struct HomeView: View {
    let session: AuthenticationSession
    let onSignOut: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("home.welcome")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("home.welcome")

                if let displayName = session.user.displayName {
                    Text(displayName)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("home.displayName")
                }

                Text("home.placeholder")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer()

                Button("home.signOut", action: onSignOut)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("home.signOut")
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(String(localized: "home.title"))
        }
    }
}

#Preview {
    HomeView(session: .mockAppleUser, onSignOut: {})
}
