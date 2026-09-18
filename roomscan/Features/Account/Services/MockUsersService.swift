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
            email: "mock@example.com",
            publicUserId: "MOCKUSER01"
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
        adoptCallerIfDifferentAccount(currentUser)
        return UserMeAPIResponse(
            id: self.currentUser.id,
            email: self.currentUser.email,
            displayName: self.currentUser.displayName,
            provider: nil,
            publicUserId: self.currentUser.publicUserId
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

        adoptCallerIfDifferentAccount(currentUser)
        self.currentUser = AuthenticatedUser(
            id: self.currentUser.id.isEmpty ? currentUser.id : self.currentUser.id,
            displayName: trimmed,
            email: self.currentUser.email ?? currentUser.email,
            publicUserId: self.currentUser.publicUserId ?? currentUser.publicUserId
        )
        return self.currentUser
    }

    /// Like the real `/users/me`, answers for whoever is signed in: a caller signed in as a
    /// different account than the one held here becomes the account this mock serves.
    private func adoptCallerIfDifferentAccount(_ caller: AuthenticatedUser) {
        if currentUser.id != caller.id {
            currentUser = caller
        }
    }

    private func simulateDelay() async throws {
        if simulatedDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: simulatedDelayNanoseconds)
        }
    }
}
