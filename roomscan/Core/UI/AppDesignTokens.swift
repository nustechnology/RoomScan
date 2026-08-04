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
    /// Figma `--rs-color-bg-brand` (#1265F6).
    static let brandPrimary = Color(red: 18 / 255, green: 101 / 255, blue: 246 / 255)
    static let brandMark = Color.white
    static let error = Color(uiColor: .systemRed)
    static let toastSuccess = Color(red: 0.11, green: 0.49, blue: 0.23)
    /// Figma `--rs-color-bg-icon-button` (#F3F6FB).
    static let iconButtonBackground = Color(red: 243 / 255, green: 246 / 255, blue: 251 / 255)
    /// Figma `--rs-color-border-default` (#DDE3EC).
    static let borderDefault = Color(red: 221 / 255, green: 227 / 255, blue: 236 / 255)
    /// Figma `--rs-color-border-strong` (#D7E0EC).
    static let borderStrong = Color(red: 215 / 255, green: 224 / 255, blue: 236 / 255)
    /// Figma `--rs-color-bg-neutral-subtle` (#EEF2F7).
    static let badgeNeutralBackground = Color(red: 238 / 255, green: 242 / 255, blue: 247 / 255)
    static let warningBannerBackground = Color(uiColor: .dynamic(
        light: UIColor(red: 1.0, green: 0.97, blue: 0.90, alpha: 1),
        dark: UIColor(red: 0.16, green: 0.14, blue: 0.06, alpha: 1)
    ))
    static let warningBannerBorder = Color(uiColor: .dynamic(
        light: UIColor(red: 0.93, green: 0.82, blue: 0.55, alpha: 1),
        dark: UIColor(red: 0.42, green: 0.34, blue: 0.15, alpha: 1)
    ))
    static let warningAction = Color(uiColor: .dynamic(
        light: UIColor(red: 0.72, green: 0.52, blue: 0.12, alpha: 1),
        dark: UIColor(red: 0.95, green: 0.79, blue: 0.36, alpha: 1)
    ))
    static let destructiveSoftBackground = Color(red: 1.0, green: 0.93, blue: 0.93)
    static let destructiveLabel = Color(red: 0.86, green: 0.18, blue: 0.18)
    static let avatarPlaceholderBackground = Color(red: 0.86, green: 0.92, blue: 1.0)
    static let avatarPlaceholderForeground = Color(red: 0.20, green: 0.47, blue: 0.96)

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

private extension UIColor {
    static func dynamic(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? dark : light
        }
    }
}
