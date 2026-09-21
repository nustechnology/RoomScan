//
//  LocalInvitationService.swift
//  roomscan
//

import Foundation

/// Client-side invitation implementation used until a backend API exists.
/// Deterministic token prefixes and UI-test scenarios support development and testing.
actor LocalInvitationService: InvitationService {
    enum Scenario: Equatable, Sendable {
        case success
        case expired
        case unavailable
        case accessDenied
        case networkFailure
    }

    private let scenario: Scenario
    private let simulatedDelayNanoseconds: UInt64
    private(set) var acceptedProjectIDs: [String] = []
    private(set) var acceptedScanIDs: [String] = []
    private(set) var declinedTokens: [String] = []

    init(
        scenario: Scenario = .success,
        simulatedDelayNanoseconds: UInt64 = 150_000_000
    ) {
        self.scenario = scenario
        self.simulatedDelayNanoseconds = simulatedDelayNanoseconds
    }

    static func makeForCurrentProcess() -> LocalInvitationService {
        let arguments = ProcessInfo.processInfo.arguments
        let delay: UInt64 = arguments.contains("-UITesting") ? 0 : 150_000_000

        if arguments.contains("-UITestInvitationExpired") {
            return LocalInvitationService(scenario: .expired, simulatedDelayNanoseconds: delay)
        }
        if arguments.contains("-UITestInvitationUnavailable") {
            return LocalInvitationService(scenario: .unavailable, simulatedDelayNanoseconds: delay)
        }
        if arguments.contains("-UITestInvitationAccessDenied") {
            return LocalInvitationService(scenario: .accessDenied, simulatedDelayNanoseconds: delay)
        }

        return LocalInvitationService(simulatedDelayNanoseconds: delay)
    }

    func fetchInvitation(
        scope: InvitationScope,
        token: String
    ) async throws -> InvitationDetails {
        try await simulateDelay()
        try throwIfForcedScenario(token: token)
        return try details(for: scope, token: token)
    }

    func acceptInvitation(
        scope: InvitationScope,
        token: String
    ) async throws -> AcceptedInvitationDestination {
        try await simulateDelay()
        try throwIfForcedScenario(token: token)
        let invitation = try details(for: scope, token: token)

        switch scope {
        case .project:
            guard let project = invitation.project else {
                throw InvitationServiceError.unavailable
            }
            acceptedProjectIDs.append(project.id)
            return .project(project)
        case .scan:
            guard let scan = invitation.scan else {
                throw InvitationServiceError.unavailable
            }
            acceptedScanIDs.append(scan.id)
            return .scan(
                SharedScanItem.make(
                    from: scan,
                    parent: SharedScanParent(
                        ownerName: invitation.ownerName,
                        projectID: "shared-project-floor-3",
                        projectName: "Company Office — Floor 3"
                    ),
                    status: .active,
                    statusChangedAt: Date()
                )
            )
        }
    }

    func declineInvitation(
        scope: InvitationScope,
        token: String
    ) async throws {
        try await simulateDelay()
        try throwIfForcedScenario(token: token)
        declinedTokens.append(token)
    }

    private func throwIfForcedScenario(token: String) throws {
        switch scenario {
        case .success:
            break
        case .expired:
            throw InvitationServiceError.expired
        case .unavailable:
            throw InvitationServiceError.unavailable
        case .accessDenied:
            throw InvitationServiceError.accessDenied
        case .networkFailure:
            throw InvitationServiceError.network
        }

        try throwIfTokenOverride(token: token)
    }

    private func throwIfTokenOverride(token: String) throws {
        if token.hasPrefix("accepted-") {
            throw InvitationServiceError.alreadyAccepted
        }
        if token.hasPrefix("declined-") {
            throw InvitationServiceError.declined
        }
        if token.hasPrefix("expired-") {
            throw InvitationServiceError.expired
        }
        if token.hasPrefix("revoked-") || token.hasPrefix("deleted-") {
            throw InvitationServiceError.unavailable
        }
        // Stands in for the server's 403 on an invitation bound to another user.
        if token.hasPrefix("mismatch-") {
            throw InvitationServiceError.accessDenied
        }
    }

    private func details(for scope: InvitationScope, token: String) throws -> InvitationDetails {
        switch scope {
        case .project:
            return projectInvitation(token: token)
        case .scan:
            return scanInvitation(token: token)
        }
    }

    private func projectInvitation(token: String) -> InvitationDetails {
        if token.hasPrefix("empty-") {
            return InvitationDetails(
                token: token,
                scope: .project,
                type: .invitation,
                title: "Empty Shared Project",
                ownerName: "Nguyen Minh Anh",
                invitedEmail: nil,
                existingAccessDestination: nil,
                itemCount: 0,
                showsThumbnail: false,
                project: ProjectSummary(
                    id: "shared-empty-project",
                    name: "Empty Shared Project",
                    ownerName: "Nguyen Minh Anh",
                    createdAt: Date(timeIntervalSince1970: 1_750_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_750_000_000),
                    description: "",
                    sharedUserCount: 1,
                    roomScans: []
                ),
                scan: nil
            )
        }

        if token.hasPrefix("share-link-") {
            return makeProjectInvitation(token: token, type: .shareLink)
        }

        return makeProjectInvitation(token: token, type: .invitation)
    }

    private func makeProjectInvitation(
        token: String,
        type: InvitationLinkType
    ) -> InvitationDetails {
        let scans = makeProjectScans()
        let project = ProjectSummary(
            id: "shared-project-floor-3",
            name: "Company Office — Floor 3",
            ownerName: "Nguyen Minh Anh",
            createdAt: Date(timeIntervalSince1970: 1_749_900_000),
            updatedAt: Date(timeIntervalSince1970: 1_750_000_000),
            description: "",
            sharedUserCount: 1,
            roomScans: scans
        )

        return InvitationDetails(
            token: token,
            scope: .project,
            type: type,
            title: project.name,
            ownerName: project.ownerName,
            invitedEmail: token.hasPrefix("mismatch-") ? "viewer@example.com" : nil,
            existingAccessDestination: nil,
            itemCount: scans.count,
            showsThumbnail: true,
            project: project,
            scan: nil
        )
    }

    private func scanInvitation(token: String) -> InvitationDetails {
        if token.hasPrefix("share-link-") {
            return makeScanInvitation(token: token, type: .shareLink)
        }
        return makeScanInvitation(token: token, type: .invitation)
    }

    private func makeScanInvitation(
        token: String,
        type: InvitationLinkType
    ) -> InvitationDetails {
        let scan = RoomScanSummary(
            id: "shared-scan-meeting-3a",
            name: "Meeting Room 3A",
            createdAt: Date(timeIntervalSince1970: 1_750_000_000),
            localModelURL: DefaultModelLoadingService.mockSampleURL,
            thumbnailName: "thumbnail-0",
            syncStatus: .synced,
            creatorUserID: "owner-nguyen",
            creatorDisplayName: "Nguyen Minh Anh",
            notes: (1...5).map { index in
                RoomScanNoteSummary(
                    id: "shared-scan-note-\(index)",
                    text: "Note \(index)",
                    createdAt: Date(timeIntervalSince1970: 1_750_000_000)
                )
            }
        )

        return InvitationDetails(
            token: token,
            scope: .scan,
            type: type,
            title: scan.name,
            ownerName: "Nguyen Minh Anh",
            invitedEmail: token.hasPrefix("mismatch-") ? "viewer@example.com" : nil,
            existingAccessDestination: nil,
            itemCount: scan.notes.count,
            showsThumbnail: true,
            project: nil,
            scan: scan
        )
    }

    private func makeProjectScans() -> [RoomScanSummary] {
        let names = ["Lobby", "Open Office", "Meeting Room 3A", "Break Room"]
        return names.enumerated().map { index, name in
            RoomScanSummary(
                id: "shared-project-scan-\(index + 1)",
                name: name,
                createdAt: Date(timeIntervalSince1970: 1_750_000_000 - Double(index) * 3_600),
                localModelURL: index == 0 ? DefaultModelLoadingService.mockSampleURL : nil,
                thumbnailName: "thumbnail-\(index % 5)",
                syncStatus: .synced,
                creatorUserID: "owner-nguyen",
                creatorDisplayName: "Nguyen Minh Anh",
                notes: []
            )
        }
    }

    private func simulateDelay() async throws {
        guard simulatedDelayNanoseconds > 0 else { return }
        try await Task.sleep(nanoseconds: simulatedDelayNanoseconds)
    }
}
