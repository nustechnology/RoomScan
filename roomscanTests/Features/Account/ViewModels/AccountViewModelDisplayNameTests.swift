//
//  AccountViewModelDisplayNameTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

@MainActor
struct AccountViewModelDisplayNameTests {
    @Test func displayNameInitialsAndProviderSubtitle() {
        #expect(AccountDisplayName.initials(from: "Mike Nguyen") == "MN")
        #expect(AccountDisplayName.initials(from: "Madonna") == "MA")
        #expect(AccountDisplayName.resolved(from: "  ") == String(localized: "account.defaultName"))
        #expect(AuthenticationProvider.apple.signedInSubtitle == String(localized: "account.signedIn.apple"))
        #expect(AuthenticationProvider.google.signedInSubtitle == String(localized: "account.signedIn.google"))
        #expect(AuthenticationProvider.facebook.signedInSubtitle == String(localized: "account.signedIn.facebook"))
    }

    @Test func openEditNameSheetPrefillsCurrentName() {
        let viewModel = AccountViewModel(
            projectsService: MockProjectsService(simulatedDelayNanoseconds: 0),
            sharedService: MockSharedService(simulatedDelayNanoseconds: 0),
            syncService: MockSyncService(simulatedDelayNanoseconds: 0)
        )

        viewModel.openEditNameSheet(currentDisplayName: "  Avery  ")

        #expect(viewModel.isEditNameSheetPresented)
        #expect(viewModel.editedDisplayName == "Avery")
        #expect(viewModel.canSaveDisplayName == false)
    }

    @Test func saveDisplayNameRejectsEmptyName() async {
        let viewModel = AccountViewModel(
            projectsService: MockProjectsService(simulatedDelayNanoseconds: 0),
            sharedService: MockSharedService(simulatedDelayNanoseconds: 0),
            syncService: MockSyncService(simulatedDelayNanoseconds: 0)
        )
        viewModel.openEditNameSheet(currentDisplayName: "Avery")
        viewModel.updateEditedDisplayName("   ")

        await viewModel.saveDisplayName(currentUser: AuthenticatedUser(
            id: "u1",
            displayName: "Avery",
            email: nil
        ))

        #expect(viewModel.isEditNameSheetPresented)
        #expect(viewModel.editValidationMessage == String(localized: "account.editName.validation.empty"))
        #expect(viewModel.isSavingDisplayName == false)
    }

    @Test func saveDisplayNameUpdatesUserAndClosesSheetOnSuccess() async {
        let usersService = MockUsersService(
            user: AuthenticatedUser(id: "u1", displayName: "Old Name", email: "a@example.com"),
            simulatedDelayNanoseconds: 0
        )
        var updatedUser: AuthenticatedUser?
        let viewModel = AccountViewModel(
            projectsService: MockProjectsService(simulatedDelayNanoseconds: 0),
            sharedService: MockSharedService(simulatedDelayNanoseconds: 0),
            syncService: MockSyncService(simulatedDelayNanoseconds: 0),
            usersService: usersService,
            onUserUpdated: { updatedUser = $0 }
        )
        let currentUser = AuthenticatedUser(id: "u1", displayName: "Old Name", email: "a@example.com")

        viewModel.openEditNameSheet(currentDisplayName: "Old Name")
        viewModel.updateEditedDisplayName("New Name")
        #expect(viewModel.canSaveDisplayName)

        await viewModel.saveDisplayName(currentUser: currentUser)

        #expect(viewModel.isEditNameSheetPresented == false)
        #expect(updatedUser?.displayName == "New Name")
        #expect(viewModel.saveErrorMessage == nil)
    }

    @Test func saveDisplayNameKeepsSheetOpenOnFailure() async {
        let usersService = MockUsersService(
            user: AuthenticatedUser(id: "u1", displayName: "Old Name", email: nil),
            scenario: .updateFailure,
            simulatedDelayNanoseconds: 0
        )
        var didUpdate = false
        let viewModel = AccountViewModel(
            projectsService: MockProjectsService(simulatedDelayNanoseconds: 0),
            sharedService: MockSharedService(simulatedDelayNanoseconds: 0),
            syncService: MockSyncService(simulatedDelayNanoseconds: 0),
            usersService: usersService,
            onUserUpdated: { _ in didUpdate = true }
        )

        viewModel.openEditNameSheet(currentDisplayName: "Old Name")
        viewModel.updateEditedDisplayName("New Name")
        await viewModel.saveDisplayName(currentUser: AuthenticatedUser(
            id: "u1",
            displayName: "Old Name",
            email: nil
        ))

        #expect(viewModel.isEditNameSheetPresented)
        #expect(viewModel.saveErrorMessage == String(localized: "account.editName.error"))
        #expect(didUpdate == false)
        #expect(viewModel.isSavingDisplayName == false)
    }

    @Test func loadProfileUpdatesUserOnSuccess() async {
        let usersService = MockUsersService(
            user: AuthenticatedUser(id: "u1", displayName: "From Server", email: "s@example.com"),
            simulatedDelayNanoseconds: 0
        )
        var updatedUser: AuthenticatedUser?
        let viewModel = AccountViewModel(
            projectsService: MockProjectsService(simulatedDelayNanoseconds: 0),
            sharedService: MockSharedService(simulatedDelayNanoseconds: 0),
            syncService: MockSyncService(simulatedDelayNanoseconds: 0),
            usersService: usersService,
            onUserUpdated: { updatedUser = $0 }
        )

        await viewModel.loadProfile(currentUser: AuthenticatedUser(
            id: "u1",
            displayName: nil,
            email: "local@example.com"
        ))

        #expect(updatedUser?.displayName == "From Server")
        #expect(updatedUser?.email == "s@example.com")
    }

    @Test func loadProfileIgnoresFailure() async {
        let usersService = MockUsersService(
            scenario: .fetchFailure,
            simulatedDelayNanoseconds: 0
        )
        var didUpdate = false
        let viewModel = AccountViewModel(
            projectsService: MockProjectsService(simulatedDelayNanoseconds: 0),
            sharedService: MockSharedService(simulatedDelayNanoseconds: 0),
            syncService: MockSyncService(simulatedDelayNanoseconds: 0),
            usersService: usersService,
            onUserUpdated: { _ in didUpdate = true }
        )

        await viewModel.loadProfile(currentUser: AuthenticatedUser(
            id: "u1",
            displayName: "Local",
            email: nil
        ))

        #expect(didUpdate == false)
    }

    @Test func saveDisplayNameIgnoresInFlightProfileLoad() async {
        let usersService = GatedFetchUsersService(
            fetchedUser: AuthenticatedUser(id: "u1", displayName: "Stale Name", email: nil)
        )
        var updatedNames: [String?] = []
        let viewModel = AccountViewModel(
            projectsService: MockProjectsService(simulatedDelayNanoseconds: 0),
            sharedService: MockSharedService(simulatedDelayNanoseconds: 0),
            syncService: MockSyncService(simulatedDelayNanoseconds: 0),
            usersService: usersService,
            onUserUpdated: { updatedNames.append($0.displayName) }
        )
        let currentUser = AuthenticatedUser(id: "u1", displayName: "Old Name", email: nil)

        let profileTask = Task {
            await viewModel.loadProfile(currentUser: currentUser)
        }
        await usersService.waitUntilFetchStarted()

        viewModel.openEditNameSheet(currentDisplayName: "Old Name")
        viewModel.updateEditedDisplayName("New Name")
        await viewModel.saveDisplayName(currentUser: currentUser)
        await usersService.releaseFetch()
        await profileTask.value

        #expect(updatedNames == ["New Name"])
    }

    @Test func userMeResponseDecodesWithoutIdAndFallsBack() throws {
        let json = Data("""
        {"email":"user@example.com","displayName":"Ada","provider":"apple"}
        """.utf8)
        let response = try JSONDecoder().decode(UserMeAPIResponse.self, from: json)
        let user = response.toAuthenticatedUser(
            fallingBackTo: AuthenticatedUser(id: "fallback-id", displayName: nil, email: nil)
        )

        #expect(user.id == "fallback-id")
        #expect(user.displayName == "Ada")
        #expect(user.email == "user@example.com")
    }

    @Test func userMeResponseDecodesWrappedUser() throws {
        let json = Data("""
        {"user":{"userId":"abc","email":"a@b.com","displayName":"Pat","provider":"apple"}}
        """.utf8)
        let response = try JSONDecoder().decode(UserMeAPIResponse.self, from: json)
        let user = response.toAuthenticatedUser(
            fallingBackTo: AuthenticatedUser(id: "fallback", displayName: nil, email: nil)
        )

        #expect(user.id == "abc")
        #expect(user.displayName == "Pat")
    }
}

private actor GatedFetchUsersService: UsersService {
    private let fetchedUser: AuthenticatedUser
    private var fetchStartedWaiters: [CheckedContinuation<Void, Never>] = []
    private var fetchReleaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var isFetchStarted = false
    private var isFetchReleased = false

    init(fetchedUser: AuthenticatedUser) {
        self.fetchedUser = fetchedUser
    }

    func waitUntilFetchStarted() async {
        if isFetchStarted { return }
        await withCheckedContinuation { continuation in
            fetchStartedWaiters.append(continuation)
        }
    }

    func releaseFetch() {
        isFetchReleased = true
        fetchReleaseWaiters.forEach { $0.resume() }
        fetchReleaseWaiters.removeAll()
    }

    func fetchMe(fallingBackTo currentUser: AuthenticatedUser) async throws -> AuthenticatedUser {
        isFetchStarted = true
        fetchStartedWaiters.forEach { $0.resume() }
        fetchStartedWaiters.removeAll()
        if !isFetchReleased {
            await withCheckedContinuation { continuation in
                fetchReleaseWaiters.append(continuation)
            }
        }
        return fetchedUser
    }

    func updateMe(
        displayName: String,
        fallingBackTo currentUser: AuthenticatedUser
    ) async throws -> AuthenticatedUser {
        AuthenticatedUser(
            id: currentUser.id,
            displayName: displayName,
            email: currentUser.email
        )
    }
}
