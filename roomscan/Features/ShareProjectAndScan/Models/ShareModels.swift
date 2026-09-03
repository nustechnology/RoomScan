//
//  ShareModels.swift
//  roomscan
//

import Foundation

enum ShareScope: String, CaseIterable, Hashable, Sendable {
    case project
    case scan
}

enum InvitationStatus: String, CaseIterable, Hashable, Sendable {
    case pending
    case accepted
}

enum SharePermission: String, CaseIterable, Hashable, Sendable {
    case viewOnly

    var title: String {
        switch self {
        case .viewOnly:
            return String(localized: "share.permission.viewOnly")
        }
    }
}

enum ShareMemberAction: String, Equatable, Sendable {
    case resendInvitation
    case cancelInvitation
    case removeAccess
}

struct InvitedMember: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let displayName: String?
    let email: String
    let initials: String
    let status: InvitationStatus
    let sentAt: Date
    let acceptedAt: Date?

    var rowTitle: String {
        let trimmedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? email : trimmedName
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

struct ShareMembersSnapshot: Equatable, Sendable {
    let members: [InvitedMember]
    let isOffline: Bool
}

enum ShareTarget: Hashable, Sendable {
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

struct ProjectTarget: Hashable, Sendable {
    let projectID: String
    let projectName: String
    let hasUploadedScan: Bool
}

struct ScanTarget: Hashable, Sendable {
    let projectID: String?
    let projectName: String?
    let scanID: String
    let scanName: String
    let syncStatus: RoomScanSyncStatus
    let assetStatus: String?
}

struct ShareScreenInput: Identifiable, Hashable, Sendable {
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

enum SharePresentation {
    static func dateText(_ date: Date, locale: Locale = .current) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().locale(locale))
    }
}
