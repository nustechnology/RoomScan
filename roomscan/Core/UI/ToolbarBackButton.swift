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

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.headline.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .foregroundStyle(foregroundColor)
        .accessibilityLabel(String(localized: "common.back"))
        .accessibilityIdentifier(accessibilityIdentifier)
        .disabled(isDisabled)
    }
}
