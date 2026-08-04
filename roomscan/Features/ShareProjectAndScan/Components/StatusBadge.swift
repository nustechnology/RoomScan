//
//  StatusBadge.swift
//  roomscan
//

import SwiftUI

struct StatusBadge: View {
    let status: InvitationStatus

    var body: some View {
        Text(title)
            .appTypography(AppTypography.labelBadge)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, AppSpacing.small)
            .padding(.vertical, 6)
            .background(backgroundColor)
            .clipShape(Capsule())
            .accessibilityIdentifier("share.status.\(status.rawValue)")
    }

    private var title: String {
        switch status {
        case .accepted:
            return String(localized: "share.status.accepted")
        case .pending:
            return String(localized: "share.status.pending")
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .accepted:
            return Color(red: 0.10, green: 0.39, blue: 0.19)
        case .pending:
            return Color(red: 0.49, green: 0.24, blue: 0.00)
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .accepted:
            return Color(red: 0.89, green: 0.96, blue: 0.91)
        case .pending:
            return Color(red: 1.00, green: 0.94, blue: 0.84)
        }
    }
}
