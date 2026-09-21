//
//  ShareModels.swift
//  roomscan
//

import Foundation

nonisolated enum ShareScope: String, CaseIterable, Hashable, Sendable {
    case project
    case scan
}

nonisolated enum InvitationStatus: String, CaseIterable, Hashable, Sendable {
    case pending
    case accepted
}

nonisolated enum SharePermission: String, CaseIterable, Hashable, Sendable {
    case viewOnly

    var title: String {
        switch self {
        case .viewOnly:
            return String(localized: "share.permission.viewOnly")
        }
    }
}

nonisolated enum ShareMemberAction: String, Equatable, Sendable {
    case resendInvitation
    case cancelInvitation
    case removeAccess
}

nonisolated struct InvitedMember: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let displayName: String?
    /// Nil for invitations addressed by public user id; set for members and for
    /// invitations addressed by email before the switch to user ids.
    let email: String?
    let publicUserId: String?
    let initials: String
    let status: InvitationStatus
    let sentAt: Date
    let acceptedAt: Date?

    static var anonymousDisplayName: String {
        String(localized: "share.member.anonymous")
    }

    var rowTitle: String {
        Self.nonBlank(displayName)
            ?? Self.nonBlank(email)
            ?? Self.nonBlank(publicUserId)
            ?? Self.anonymousDisplayName
    }

    /// Resend responses omit the display name, and the recipient is unchanged, so this
    /// keeps the row's identity and takes only the delivery state from the server.
    func updatedByResend(_ resent: InvitedMember) -> InvitedMember {
        InvitedMember(
            id: resent.id,
            displayName: displayName ?? resent.displayName,
            email: email ?? resent.email,
            publicUserId: publicUserId ?? resent.publicUserId,
            initials: initials,
            status: resent.status,
            sentAt: resent.sentAt,
            acceptedAt: resent.acceptedAt
        )
    }

    /// Nil when there is no id, or when the id is already shown as the row title.
    var publicUserIdLabel: String? {
        guard let publicUserId = Self.nonBlank(publicUserId), publicUserId != rowTitle else {
            return nil
        }
        return String.localizedStringWithFormat(
            String(localized: "share.member.publicUserId.format"),
            publicUserId
        )
    }

    static func initials(displayName: String?, email: String?, publicUserId: String?) -> String {
        if let displayName = nonBlank(displayName) {
            return AccountDisplayName.initials(from: displayName)
        }
        if let email = nonBlank(email) {
            return initials(for: email)
        }
        if let publicUserId = nonBlank(publicUserId) {
            return String(publicUserId.prefix(2)).uppercased()
        }
        return "?"
    }

    static func initials(for email: String) -> String {
        let base = email.split(separator: "@").first.map(String.init) ?? email
        let letters = base
            .split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" })
            .prefix(2)
            .compactMap { $0.first.map { String($0).uppercased() } }
        let result = letters.joined()
        return result.isEmpty ? "?" : result
    }

    /// The feature's single rule for blank server strings: trimmed, or nil when empty.
    static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    var subtitle: String {
        let dateText: String
        switch status {
        case .accepted:
            dateText = SharePresentation.dateText(acceptedAt ?? sentAt)
            return String.localizedStringWithFormat(
                String(localized: "share.member.accepted.format"),
                dateText
            )
        case .pending:
            dateText = SharePresentation.dateText(sentAt)
            return String.localizedStringWithFormat(
                String(localized: "share.member.sent.format"),
                dateText
            )
        }
    }
}

nonisolated struct ShareMembersSnapshot: Equatable, Sendable {
    let members: [InvitedMember]
    let isOffline: Bool
}

nonisolated enum ShareTarget: Hashable, Sendable {
    case project(ProjectTarget)
    case scan(ScanTarget)

    var id: String {
        switch self {
        case .project(let target):
            return target.projectID
        case .scan(let target):
            return target.scanID
        }
    }

    var displayTitle: String {
        switch self {
        case .project(let target):
            return target.projectName
        case .scan(let target):
            return target.scanName
        }
    }
}

nonisolated struct ProjectTarget: Hashable, Sendable {
    let projectID: String
    let projectName: String
    let hasUploadedScan: Bool
}

nonisolated struct ScanTarget: Hashable, Sendable {
    let projectID: String?
    let projectName: String?
    let scanID: String
    let scanName: String
    let syncStatus: RoomScanSyncStatus
    let assetStatus: String?
}

nonisolated struct ShareScreenInput: Identifiable, Hashable, Sendable {
    let id: String
    let scope: ShareScope
    let target: ShareTarget
    let targetID: String

    var isShareReady: Bool {
        switch target {
        case .project(let project):
            return project.hasUploadedScan
        case .scan(let scan):
            return RoomScanSummary.isReadyToShare(
                syncStatus: scan.syncStatus,
                assetStatus: scan.assetStatus
            )
        }
    }

    var titleText: String {
        target.displayTitle
    }

    var screenTitle: String {
        String(localized: "share.screenTitle")
    }

    var descriptionText: String {
        switch scope {
        case .project:
            return String(localized: "share.description.project")
        case .scan:
            return String(localized: "share.description.scan")
        }
    }

    var emptyStateTitle: String {
        switch scope {
        case .project:
            return String(localized: "share.empty.project.title")
        case .scan:
            return String(localized: "share.empty.scan.title")
        }
    }

    var emptyStateMessage: String {
        String(localized: "share.empty.message")
    }

    static func project(id: String, name: String, hasUploadedScan: Bool = false) -> ShareScreenInput {
        ShareScreenInput(
            id: "\(ShareScope.project.rawValue)-\(id)",
            scope: .project,
            target: .project(
                ProjectTarget(projectID: id, projectName: name, hasUploadedScan: hasUploadedScan)
            ),
            targetID: id
        )
    }

    static func scan(
        projectID: String?,
        projectName: String?,
        scanID: String,
        scanName: String,
        syncStatus: RoomScanSyncStatus,
        assetStatus: String? = nil
    ) -> ShareScreenInput {
        ShareScreenInput(
            id: "\(ShareScope.scan.rawValue)-\(scanID)",
            scope: .scan,
            target: .scan(
                ScanTarget(
                    projectID: projectID,
                    projectName: projectName,
                    scanID: scanID,
                    scanName: scanName,
                    syncStatus: syncStatus,
                    assetStatus: assetStatus
                )
            ),
            targetID: scanID
        )
    }
}

nonisolated enum SharePresentation {
    static func dateText(_ date: Date, locale: Locale = .current) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().locale(locale))
    }
}
