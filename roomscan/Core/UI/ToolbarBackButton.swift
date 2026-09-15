//
//  ToolbarBackButton.swift
//  roomscan
//

import SwiftUI

struct ToolbarBackButton: View {
    let action: () -> Void
    let accessibilityIdentifier: String
    var isDisabled = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.headline.weight(.semibold))
                .frame(width: 36, height: 36)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .accessibilityLabel(String(localized: "common.back"))
        .accessibilityIdentifier(accessibilityIdentifier)
        .disabled(isDisabled)
    }
}
