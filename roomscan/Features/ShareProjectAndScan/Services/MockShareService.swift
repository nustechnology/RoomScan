//
//  MockShareService.swift
//  roomscan
//

import Foundation
import UIKit

actor MockShareService: ShareService {
    enum Scenario: Equatable, Sendable {
        case success
        case empty
        case offline
        case loadFailure
    }

    private struct Storage: Sendable {
        var membersByInputID: [String: [InvitedMember]]
        var isOffline: Bool
    }

    private let simulatedDelayNanoseconds: UInt64
    private var storage: Storage
    private let scenario: Scenario

    init(
        scenario: Scenario = .success,
        simulatedDelayNanoseconds: UInt64 = 120_000_000
    ) {
        self.scenario = scenario
        self.simulatedDelayNanoseconds = simulatedDelayNanoseconds
        self.storage = Storage(
            membersByInputID: MockShareService.seedMembers(for: scenario),
            isOffline: scenario == .offline
        )
    }

    static func makeForCurrentProcess() -> MockShareService {
        let arguments = ProcessInfo.processInfo.arguments
        let delay: UInt64 = arguments.contains("-UITesting") ? 0 : 120_000_000

        if arguments.contains("-UITestShareEmpty") {
            return MockShareService(scenario: .empty, simulatedDelayNanoseconds: delay)
        }

        if arguments.contains("-UITestShareOffline") {
            return MockShareService(scenario: .offline, simulatedDelayNanoseconds: delay)
        }

        if arguments.contains("-UITestShareLoadFailure") {
            return MockShareService(scenario: .loadFailure, simulatedDelayNanoseconds: delay)
        }

        return MockShareService(simulatedDelayNanoseconds: delay)
    }

    func loadInvitedMembers(for input: ShareScreenInput) async throws -> ShareMembersSnapshot {
        try await simulateDelay()

        if scenario == .loadFailure {
            throw ShareServiceError.unavailable
        }

        return ShareMembersSnapshot(
            members: storage.membersByInputID[input.id, default: []],
            isOffline: storage.isOffline
        )
    }

    func sendInvitation(for input: ShareScreenInput, email: String) async throws -> InvitedMember {
        try await simulateDelay()
        try ensureOnline()

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let existingMembers = storage.membersByInputID[input.id, default: []]
        if existingMembers.contains(where: { $0.email.lowercased() == normalizedEmail }) {
            throw ShareServiceError.duplicateEmail
        }

        let member = InvitedMember(
            id: "invite-\(UUID().uuidString)",
            displayName: nil,
            email: normalizedEmail,
            initials: Self.initials(for: normalizedEmail),
            status: .pending,
            sentAt: Date(),
            acceptedAt: nil
        )

        storage.membersByInputID[input.id, default: []].insert(member, at: 0)
        return member
    }

    func resendInvitation(for input: ShareScreenInput, id: String) async throws -> InvitedMember {
        try await simulateDelay()
        try ensureOnline()

        guard var members = storage.membersByInputID[input.id],
              let index = members.firstIndex(where: { $0.id == id }) else {
            throw ShareServiceError.memberNotFound
        }

        let existing = members[index]
        let updated = InvitedMember(
            id: existing.id,
            displayName: existing.displayName,
            email: existing.email,
            initials: existing.initials,
            status: .pending,
            sentAt: Date(),
            acceptedAt: nil
        )
        members[index] = updated
        storage.membersByInputID[input.id] = members
        return updated
    }

    func revokeInvitation(for input: ShareScreenInput, id: String) async throws {
        try await simulateDelay()
        try ensureOnline()
        try removeMember(for: input, id: id)
    }

    func revokeAccess(for input: ShareScreenInput, userID: String) async throws {
        try await simulateDelay()
        try ensureOnline()
        try removeMember(for: input, id: userID)
    }

    func copyInvitationLink(for input: ShareScreenInput) async throws -> URL {
        try await simulateDelay()
        try ensureOnline()

        let pathComponent: String
        switch input.scope {
        case .project:
            pathComponent = "projects"
        case .scan:
            pathComponent = "scans"
        }

        let encodedTargetID = input.targetID
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        guard let url = URL(
            string: "https://roomscan.app/\(pathComponent)/\(encodedTargetID)/share"
        ) else {
            throw ShareServiceError.unavailable
        }
        await MainActor.run {
            UIPasteboard.general.string = url.absoluteString
        }
        return url
    }

    private func removeMember(for input: ShareScreenInput, id: String) throws {
        guard var members = storage.membersByInputID[input.id] else {
            throw ShareServiceError.memberNotFound
        }

        let originalCount = members.count
        members.removeAll { $0.id == id }
        guard members.count != originalCount else {
            throw ShareServiceError.memberNotFound
        }
        storage.membersByInputID[input.id] = members
    }

    private func ensureOnline() throws {
        if storage.isOffline {
            throw ShareServiceError.offline
        }
    }

    private func simulateDelay() async throws {
        try await Task.sleep(nanoseconds: simulatedDelayNanoseconds)
    }

    private static func seedMembers(for scenario: Scenario) -> [String: [InvitedMember]] {
        let projectInput = ShareScreenInput.project(id: "project-1", name: "Lakeside Remodel")
        let scanInput = ShareScreenInput.scan(
            projectID: "project-1",
            projectName: "Lakeside Remodel",
            scanID: "scan-1",
            scanName: "Living Room"
        )

        if scenario == .empty {
            return [
                projectInput.id: [],
                scanInput.id: []
            ]
        }

        return [
            projectInput.id: [
                InvitedMember(
                    id: "member-1",
                    displayName: "Avery Stone",
                    email: "avery@example.com",
                    initials: "AS",
                    status: .accepted,
                    sentAt: makeDate(year: 2026, month: 6, day: 6),
                    acceptedAt: makeDate(year: 2026, month: 6, day: 10)
                ),
                InvitedMember(
                    id: "member-2",
                    displayName: nil,
                    email: "morgan@example.com",
                    initials: "MO",
                    status: .pending,
                    sentAt: makeDate(year: 2026, month: 7, day: 18),
                    acceptedAt: nil
                )
            ],
            scanInput.id: [
                InvitedMember(
                    id: "member-3",
                    displayName: "Taylor Chen",
                    email: "taylor@example.com",
                    initials: "TC",
                    status: .accepted,
                    sentAt: makeDate(year: 2026, month: 6, day: 16),
                    acceptedAt: makeDate(year: 2026, month: 6, day: 21)
                )
            ]
        ]
    }

    nonisolated private static func initials(for email: String) -> String {
        let base = email.split(separator: "@").first.map(String.init) ?? email
        let letters = base
            .split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" })
            .prefix(2)
            .compactMap { $0.first.map { String($0).uppercased() } }
        let result = letters.joined()
        return result.isEmpty ? "?" : result
    }

    private static func makeDate(year: Int, month: Int, day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }
}
