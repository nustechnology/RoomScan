//
//  ToolbarBackButton.swift
//  roomscan
//

import SwiftUI

struct ToolbarBackButton: View {
    let action: () -> Void
    let accessibilityIdentifier: String
    var isDisabled = false
    var foregroundColor: Color = .primary
    var accessibilityLabel: String = String(localized: "common.back")

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.headline.weight(.semibold))
                .frame(width: 36, height: 36)
                .padding(4)
                .contentShape(Rectangle())
        }
        .foregroundStyle(foregroundColor)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
        .disabled(isDisabled)
    }
}
