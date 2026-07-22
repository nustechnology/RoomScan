//
//  PrimaryActionButton.swift
//  roomscan
//

import SwiftUI

struct PrimaryActionButton: View {
    let title: String
    let systemImageName: String
    let color: Color
    let action: () -> Void
    var accessibilityIdentifier: String?

    var body: some View {
        Button(
            action: action,
            label: {
                Label(title, systemImage: systemImageName)
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
            }
        )
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: color.opacity(0.28), radius: 10, x: 0, y: 5)
        .applyAccessibilityIdentifier(accessibilityIdentifier)
    }
}

private extension View {
    @ViewBuilder
    func applyAccessibilityIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}

#Preview {
    PrimaryActionButton(
        title: "New Scan",
        systemImageName: "plus",
        color: .blue,
        action: {}
    )
    .padding()
}
