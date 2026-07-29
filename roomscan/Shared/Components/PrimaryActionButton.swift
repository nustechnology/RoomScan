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
    var font: Font = .title2.bold()
    var foregroundColor: Color = .white
    var borderColor: Color?
    var borderWidth: CGFloat = 1
    var cornerRadius: CGFloat = 12
    var accessibilityIdentifier: String?

    var body: some View {
        Button(
            action: action,
            label: {
                Group {
                    if let systemImageName {
                        Label(title, systemImage: systemImageName)
                    } else {
                        Text(title)
                    }
                }
                .font(font)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
            }
        )
        .buttonStyle(.plain)
        .foregroundStyle(foregroundColor)
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
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
        title: "New Scan",
        systemImageName: "plus",
        color: .blue,
        action: {}
    )
    .padding()
}
