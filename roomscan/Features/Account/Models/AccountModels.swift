//
//  AccountModels.swift
//  roomscan
//

import Foundation

struct AccountMetrics: Equatable, Sendable {
    let localScanCount: Int
    let pendingSyncCount: Int
    let sharedProjectCount: Int
    let storageUsedBytes: Int64

    var showsSyncPendingBanner: Bool {
        pendingSyncCount > 0
    }

    var formattedStorageUsed: String {
        AccountMetrics.byteFormatter.string(fromByteCount: storageUsedBytes)
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()
}

/// Nonisolated under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` so
/// nonisolated mappers (e.g. `ShareAPIMapping`) can compute display names.
nonisolated enum AccountDisplayName {
    static func resolved(from displayName: String?) -> String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return String(localized: "account.defaultName")
        }
        return trimmed
    }

    static func initials(from displayName: String?) -> String {
        let resolved = resolved(from: displayName)
        let parts = resolved
            .split(whereSeparator: \.isWhitespace)
            .filter { !$0.isEmpty }

        if parts.count >= 2 {
            let first = parts[0].prefix(1)
            let second = parts[1].prefix(1)
            return String(first + second).uppercased()
        }

        if let first = parts.first {
            return String(first.prefix(2)).uppercased()
        }

        return "U"
    }
}

extension AuthenticationProvider {
    var signedInSubtitle: String {
        switch self {
        case .apple:
            String(localized: "account.signedIn.apple")
        case .google:
            String(localized: "account.signedIn.google")
        case .facebook:
            String(localized: "account.signedIn.facebook")
        }
    }
}
