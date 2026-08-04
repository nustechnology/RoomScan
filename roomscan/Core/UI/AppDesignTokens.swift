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
    static let toastSuccess = Color(red: 0.11, green: 0.49, blue: 0.23)

    static let noteRed = Color(red: 0.90, green: 0.22, blue: 0.21)
    static let noteOrange = Color(red: 0.96, green: 0.53, blue: 0.12)
    static let noteYellow = Color(red: 0.98, green: 0.80, blue: 0.08)
    static let noteGreen = Color(red: 0.22, green: 0.72, blue: 0.35)
    static let noteCyan = Color(red: 0.20, green: 0.74, blue: 0.82)
    static let noteBlue = Color(red: 0.20, green: 0.47, blue: 0.96)
    static let notePurple = Color(red: 0.56, green: 0.27, blue: 0.88)
    static let noteGray = Color(red: 0.56, green: 0.58, blue: 0.62)
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
