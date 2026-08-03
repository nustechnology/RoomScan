//
//  SharedAccessStatusBadge.swift
//  roomscan
//

import SwiftUI

struct SharedAccessStatusBadge: View {
    let status: SharedAccessStatus
    let scope: SharedItemScope

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(foregroundColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(status.localizedTitle(for: scope))
                .font(.system(size: 12, weight: .black))
                .lineLimit(1)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(foregroundColor.opacity(0.16))
        .clipShape(Capsule())
        .accessibilityIdentifier("shared.status.\(status.rawValue)")
    }

    private var foregroundColor: Color {
        switch status {
        case .active:
            return .green
        case .accessRevoked, .itemDeleted:
            return .red
        }
    }
}

extension SharedAccessStatus {
    func localizedTitle(for scope: SharedItemScope) -> String {
        switch self {
        case .active:
            return String(localized: "shared.status.active")
        case .accessRevoked:
            return String(localized: "shared.status.accessRevoked")
        case .itemDeleted:
            switch scope {
            case .project:
                return String(localized: "shared.status.projectDeleted")
            case .scan:
                return String(localized: "shared.status.scanDeleted")
            }
        }
    }

    func helperText(for scope: SharedItemScope) -> String {
        switch (self, scope) {
        case (.active, _):
            return ""
        case (.accessRevoked, .project):
            return String(localized: "shared.helper.project.accessRevoked")
        case (.accessRevoked, .scan):
            return String(localized: "shared.helper.scan.accessRevoked")
        case (.itemDeleted, .project):
            return String(localized: "shared.helper.project.deleted")
        case (.itemDeleted, .scan):
            return String(localized: "shared.helper.scan.deleted")
        }
    }
}
