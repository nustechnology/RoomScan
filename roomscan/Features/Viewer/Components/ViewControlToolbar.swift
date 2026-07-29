//
//  ViewControlToolbar.swift
//  roomscan
//

import SwiftUI

struct ViewControlToolbar: View {
    let isFullscreen: Bool
    let isEnabled: Bool
    let onToggleFullscreen: () -> Void
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.small) {
            toolbarButton(
                systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                accessibilityLabel: isFullscreen
                    ? String(localized: "viewer.toolbar.exitFullscreen")
                    : String(localized: "viewer.toolbar.fullscreen"),
                action: onToggleFullscreen
            )
            toolbarButton(
                systemName: "plus",
                accessibilityLabel: String(localized: "viewer.toolbar.zoomIn"),
                action: onZoomIn
            )
            toolbarButton(
                systemName: "minus",
                accessibilityLabel: String(localized: "viewer.toolbar.zoomOut"),
                action: onZoomOut
            )
            toolbarButton(
                systemName: "scope",
                accessibilityLabel: String(localized: "viewer.toolbar.reset"),
                action: onReset
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("viewer.toolbar")
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private func toolbarButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppColors.primaryText)
                .frame(minWidth: 44, minHeight: 44)
                .background(AppColors.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: Color.black.opacity(0.08), radius: 4, y: 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
