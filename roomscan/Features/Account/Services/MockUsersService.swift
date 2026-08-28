//
//  MockUsersService.swift
//  roomscan
//

import Foundation

actor MockUsersService: UsersService {
    enum Scenario: Equatable, Sendable {
        case success
        case fetchFailure
        case updateFailure
    }

    private var currentUser: AuthenticatedUser
    private var scenario: Scenario
    private let simulatedDelayNanoseconds: UInt64

    init(
        user: AuthenticatedUser = AuthenticatedUser(
            id: "mock-user",
            displayName: "Mock User",
            email: "mock@example.com"
        ),
        scenario: Scenario = .success,
        simulatedDelayNanoseconds: UInt64 = 0
    ) {
        self.currentUser = user
        self.scenario = scenario
        self.simulatedDelayNanoseconds = simulatedDelayNanoseconds
    }

    static func makeForCurrentProcess() -> MockUsersService {
        let delay: UInt64 = ProcessInfo.processInfo.arguments.contains("-UITesting") ? 0 : 80_000_000
        return MockUsersService(simulatedDelayNanoseconds: delay)
    }

    func setScenario(_ scenario: Scenario) {
        self.scenario = scenario
    }

    func setCurrentUser(_ user: AuthenticatedUser) {
        currentUser = user
    }

    func fetchMe(fallingBackTo currentUser: AuthenticatedUser) async throws -> AuthenticatedUser {
        try await simulateDelay()
        if scenario == .fetchFailure {
            throw UsersServiceError.network
        }
        return UserMeAPIResponse(
            id: self.currentUser.id,
            email: self.currentUser.email,
            displayName: self.currentUser.displayName,
            provider: nil
        ).toAuthenticatedUser(fallingBackTo: currentUser)
    }

    func fetchRemoteDisplayName() async throws -> String? {
        try await simulateDelay()
        if scenario == .fetchFailure {
            throw UsersServiceError.network
        }
        return AppleUserDisplayName.nonBlank(currentUser.displayName)
    }

    func updateMe(
        displayName: String,
        fallingBackTo currentUser: AuthenticatedUser
    ) async throws -> AuthenticatedUser {
        try await simulateDelay()

        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw UsersServiceError.invalidDisplayName
        }

        if scenario == .updateFailure {
            throw UsersServiceError.server
        }

        self.currentUser = AuthenticatedUser(
            id: self.currentUser.id.isEmpty ? currentUser.id : self.currentUser.id,
            displayName: trimmed,
            email: self.currentUser.email ?? currentUser.email
        )
        return self.currentUser
    }

    private func simulateDelay() async throws {
        if simulatedDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: simulatedDelayNanoseconds)
        }
    }
}
