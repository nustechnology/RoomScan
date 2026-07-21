//
//  AppDesignTokens.swift
//  roomscan
//

import SwiftUI

enum AppColors {
    static let background = Color(uiColor: .systemBackground)
    static let primaryText = Color(uiColor: .label)
    static let secondaryText = Color(uiColor: .secondaryLabel)
    static let primaryAction = Color(red: 0.04, green: 0.05, blue: 0.08)
    static let primaryActionLabel = Color.white
    static let brandBlueTop = Color(red: 0.04, green: 0.53, blue: 1)
    static let brandBlueBottom = Color(red: 0.02, green: 0.36, blue: 0.88)
    static let brandMark = Color.white
    static let error = Color(uiColor: .systemRed)
}

enum AppSpacing {
    static let extraSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let extraLarge: CGFloat = 24
    static let doubleExtraLarge: CGFloat = 32
    static let tripleExtraLarge: CGFloat = 48
}

enum AppCornerRadius {
    static let medium: CGFloat = 16
    static let large: CGFloat = 20
}

enum AppShadows {
    static let logoColor = Color.black.opacity(0.18)
    static let actionColor = Color.black.opacity(0.14)
}
