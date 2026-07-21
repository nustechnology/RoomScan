//
//  AppTypography.swift
//  roomscan
//

import SwiftUI

struct AppTypographyStyle {
    let size: CGFloat
    let lineHeight: CGFloat
    let weight: Font.Weight
    let relativeTo: Font.TextStyle
    let tracking: CGFloat

    init(
        size: CGFloat,
        lineHeight: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo: Font.TextStyle,
        tracking: CGFloat = 0
    ) {
        self.size = size
        self.lineHeight = lineHeight
        self.weight = weight
        self.relativeTo = relativeTo
        self.tracking = tracking
    }
}

enum AppTypography {
    static let displayXL = AppTypographyStyle(
        size: 30,
        lineHeight: 31,
        weight: .bold,
        relativeTo: .largeTitle,
        tracking: -1.65
    )

    static let headingLarge = AppTypographyStyle(
        size: 23,
        lineHeight: 25,
        weight: .bold,
        relativeTo: .title2
    )
    static let headingMedium = AppTypographyStyle(
        size: 19,
        lineHeight: 24,
        weight: .bold,
        relativeTo: .title3
    )
    static let headingSmall = AppTypographyStyle(
        size: 17,
        lineHeight: 21,
        weight: .bold,
        relativeTo: .headline
    )

    static let bodyLarge = AppTypographyStyle(
        size: 16,
        lineHeight: 23,
        relativeTo: .body
    )
    static let bodyLargeStrong = AppTypographyStyle(
        size: 16,
        lineHeight: 23,
        weight: .bold,
        relativeTo: .body
    )
    static let bodyMedium = AppTypographyStyle(
        size: 15,
        lineHeight: 22,
        relativeTo: .subheadline
    )
    static let bodyMediumStrong = AppTypographyStyle(
        size: 15,
        lineHeight: 22,
        weight: .bold,
        relativeTo: .subheadline
    )
    static let bodySmall = AppTypographyStyle(
        size: 14,
        lineHeight: 20,
        relativeTo: .subheadline
    )
    static let bodySmallStrong = AppTypographyStyle(
        size: 14,
        lineHeight: 20,
        weight: .bold,
        relativeTo: .subheadline
    )

    static let captionMedium = AppTypographyStyle(
        size: 12,
        lineHeight: 17,
        relativeTo: .caption
    )
    static let captionMediumStrong = AppTypographyStyle(
        size: 12,
        lineHeight: 17,
        weight: .bold,
        relativeTo: .caption
    )

    static let labelButton = AppTypographyStyle(
        size: 17,
        lineHeight: 22,
        weight: .heavy,
        relativeTo: .headline
    )
    static let labelBadge = AppTypographyStyle(
        size: 11,
        lineHeight: 14,
        weight: .bold,
        relativeTo: .caption2
    )
    static let labelTab = AppTypographyStyle(
        size: 11,
        lineHeight: 14,
        weight: .semibold,
        relativeTo: .caption2
    )
    static let labelField = AppTypographyStyle(
        size: 12,
        lineHeight: 16,
        weight: .bold,
        relativeTo: .caption
    )
    static let labelStatus = AppTypographyStyle(
        size: 13,
        lineHeight: 16,
        weight: .bold,
        relativeTo: .footnote
    )
    static let labelTiny = AppTypographyStyle(
        size: 10.5,
        lineHeight: 15,
        relativeTo: .caption2
    )
}

private struct AppTypographyModifier: ViewModifier {
    let style: AppTypographyStyle

    @ScaledMetric private var size: CGFloat
    @ScaledMetric private var lineHeight: CGFloat
    @ScaledMetric private var tracking: CGFloat

    init(style: AppTypographyStyle) {
        self.style = style
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
        _lineHeight = ScaledMetric(
            wrappedValue: style.lineHeight,
            relativeTo: style.relativeTo
        )
        _tracking = ScaledMetric(
            wrappedValue: style.tracking,
            relativeTo: style.relativeTo
        )
    }

    func body(content: Content) -> some View {
        content
            .font(.custom("Inter", size: size))
            .fontWeight(style.weight)
            .tracking(tracking)
            .lineSpacing(max(0, lineHeight - size))
    }
}

extension View {
    func appTypography(_ style: AppTypographyStyle) -> some View {
        modifier(AppTypographyModifier(style: style))
    }
}
