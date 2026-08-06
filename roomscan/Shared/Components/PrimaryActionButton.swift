//
//  PrimaryActionButton.swift
//  roomscan
//

import SwiftUI

struct PrimaryActionButton: View {
    let title: String
    let systemImageName: String?
    let color: Color
    let action: () -> Void
    var typography: AppTypographyStyle = AppTypography.labelButton
    var foregroundColor: Color = .white
    var borderColor: Color?
    var borderWidth: CGFloat = 1
    var cornerRadius: CGFloat = 18
    var accessibilityIdentifier: String?

    var body: some View {
        Button(
            action: action,
            label: {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(color)

                    Group {
                        if let systemImageName {
                            Label(title, systemImage: systemImageName)
                        } else {
                            Text(title)
                        }
                    }
                    .appTypography(typography)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
        )
        .buttonStyle(.plain)
        .foregroundStyle(foregroundColor)
        .overlay {
            if let borderColor {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: borderWidth)
            }
        }
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
        title: String(localized: "projects.detail.addScan"),
        systemImageName: "plus",
        color: AppColors.background,
        action: {}
    )
    .padding()
}
