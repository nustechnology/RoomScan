//
//  RemoteAuthenticationServiceTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

@MainActor
struct RemoteAuthenticationServiceTests {
    @Test func persistAppleSessionUsesResolvedDisplayNameAndStoresIt() throws {
        let keychain = InMemoryKeychainStore()
        let service = RemoteAuthenticationService(
            httpClient: UnusedHTTPClient(),
            keychainStore: keychain
        )
        var appleName = PersonNameComponents()
        appleName.givenName = "Jane"
        appleName.familyName = "Doe"
        let expectedName = AppleUserDisplayName.formatted(from: appleName)

        let session = try service.persistAppleSession(
            from: .sample(displayName: "API Name"),
            appleFullName: appleName
        )

        #expect(session.user.displayName == expectedName)
        #expect(session.user.email == "jane@example.com")
        #expect(session.user.publicUserId == "JANEDOE123")
        #expect(keychain.stored?.userDisplayName == expectedName)
        #expect(keychain.stored?.userId == "user-1")
        #expect(keychain.stored?.userPublicId == "JANEDOE123")
        #expect(keychain.stored?.needsDisplayNameUpload == false)
    }

    @Test func persistAppleSessionMarksUploadWhenAPIHasNoName() throws {
        let keychain = InMemoryKeychainStore()
        let service = RemoteAuthenticationService(
            httpClient: UnusedHTTPClient(),
            keychainStore: keychain
        )
        var appleName = PersonNameComponents()
        appleName.givenName = "Jane"
        appleName.familyName = "Doe"

        _ = try service.persistAppleSession(
            from: .sample(displayName: nil),
            appleFullName: appleName
        )

        #expect(keychain.stored?.needsDisplayNameUpload == true)
        #expect(keychain.stored?.userDisplayName == AppleUserDisplayName.formatted(from: appleName))
    }

    @Test func persistAppleSessionFallsBackToAPIDisplayName() throws {
        let keychain = InMemoryKeychainStore()
        let service = RemoteAuthenticationService(
            httpClient: UnusedHTTPClient(),
            keychainStore: keychain
        )

        let session = try service.persistAppleSession(
            from: .sample(displayName: "API Name"),
            appleFullName: nil
        )

        #expect(session.user.displayName == "API Name")
        #expect(keychain.stored?.userDisplayName == "API Name")
        #expect(keychain.stored?.needsDisplayNameUpload == false)
    }

    @Test func completeAppleSignInUploadsAppleNameWhenAPIHasNone() async throws {
        let keychain = InMemoryKeychainStore()
        let usersService = RecordingUsersService()
        let service = RemoteAuthenticationService(
            httpClient: UnusedHTTPClient(),
            keychainStore: keychain,
            usersService: usersService
        )
        var appleName = PersonNameComponents()
        appleName.givenName = "Jane"
        appleName.familyName = "Doe"
        let expectedName = try #require(AppleUserDisplayName.formatted(from: appleName))

        let session = try await service.completeAppleSignIn(
            from: .sample(displayName: nil),
            appleFullName: appleName
        )

        #expect(session.user.displayName == expectedName)
        #expect(await usersService.updateCalls == [expectedName])
        #expect(keychain.stored?.needsDisplayNameUpload == false)
    }

    @Test func completeAppleSignInDoesNotUploadWhenAPIAlreadyHasName() async throws {
        let keychain = InMemoryKeychainStore()
        let usersService = RecordingUsersService()
        let service = RemoteAuthenticationService(
            httpClient: UnusedHTTPClient(),
            keychainStore: keychain,
            usersService: usersService
        )
        var appleName = PersonNameComponents()
        appleName.givenName = "Jane"
        appleName.familyName = "Doe"

        _ = try await service.completeAppleSignIn(
            from: .sample(displayName: "Existing"),
            appleFullName: appleName
        )

        #expect(await usersService.updateCalls.isEmpty)
        #expect(keychain.stored?.needsDisplayNameUpload == false)
    }

    @Test func completeAppleSignInSucceedsWhenUploadFails() async throws {
        let keychain = InMemoryKeychainStore()
        let usersService = RecordingUsersService()
        await usersService.setUpdateError(.network)
        let service = RemoteAuthenticationService(
            httpClient: UnusedHTTPClient(),
            keychainStore: keychain,
            usersService: usersService
        )
        var appleName = PersonNameComponents()
        appleName.givenName = "Jane"
        appleName.familyName = "Doe"

        let session = try await service.completeAppleSignIn(
            from: .sample(displayName: nil),
            appleFullName: appleName
        )

        #expect(session.user.displayName == AppleUserDisplayName.formatted(from: appleName))
        #expect(keychain.stored?.needsDisplayNameUpload == true)
    }

    @Test func restoreSessionRetriesDisplayNameUpload() async throws {
        let keychain = InMemoryKeychainStore()
        keychain.stored = StoredAuthData(
            accessToken: "old-access",
            refreshToken: "old-refresh",
            userId: "user-1",
            userEmail: "jane@example.com",
            userDisplayName: "Jane Doe",
            needsDisplayNameUpload: true
        )
        let usersService = RecordingUsersService()
        let client = AuthHTTPClient { _ in
            .success(Data(#"{"accessToken":"new-access","refreshToken":"new-refresh"}"#.utf8))
        }
        let service = RemoteAuthenticationService(
            httpClient: client,
            keychainStore: keychain,
            usersService: usersService
        )

        let session = try await service.restoreSession()

        #expect(session?.user.displayName == "Jane Doe")
        #expect(await usersService.updateCalls == ["Jane Doe"])
        #expect(keychain.stored?.needsDisplayNameUpload == false)
        #expect(keychain.stored?.accessToken == "new-access")
    }

    @Test func restoreSessionDoesNotClobberExistingRemoteDisplayName() async throws {
        let keychain = InMemoryKeychainStore()
        keychain.stored = StoredAuthData(
            accessToken: "old-access",
            refreshToken: "old-refresh",
            userId: "user-1",
            userEmail: "jane@example.com",
            userDisplayName: "Jane Doe",
            needsDisplayNameUpload: true
        )
        let usersService = RecordingUsersService(remoteDisplayName: "Bob")
        let client = AuthHTTPClient { _ in
            .success(Data(#"{"accessToken":"new-access","refreshToken":"new-refresh"}"#.utf8))
        }
        let service = RemoteAuthenticationService(
            httpClient: client,
            keychainStore: keychain,
            usersService: usersService
        )

        _ = try await service.restoreSession()

        #expect(await usersService.updateCalls.isEmpty)
        #expect(keychain.stored?.needsDisplayNameUpload == false)
    }

    @Test func restoreSessionKeepsUploadFlagWhenRetryFails() async throws {
        let keychain = InMemoryKeychainStore()
        keychain.stored = StoredAuthData(
            accessToken: "old-access",
            refreshToken: "old-refresh",
            userId: "user-1",
            userEmail: "jane@example.com",
            userDisplayName: "Jane Doe",
            needsDisplayNameUpload: true
        )
        let usersService = RecordingUsersService()
        await usersService.setUpdateError(.network)
        let client = AuthHTTPClient { _ in
            .success(Data(#"{"accessToken":"new-access","refreshToken":"new-refresh"}"#.utf8))
        }
        let service = RemoteAuthenticationService(
            httpClient: client,
            keychainStore: keychain,
            usersService: usersService
        )

        let session = try await service.restoreSession()

        #expect(session?.user.displayName == "Jane Doe")
        #expect(keychain.stored?.needsDisplayNameUpload == true)
    }

    @Test func displayNameUploadPreservesTokensRotatedDuringSync() async throws {
        let keychain = InMemoryKeychainStore()
        let usersService = RecordingUsersService()
        await usersService.setOnUpdate {
            keychain.stored = StoredAuthData(
                accessToken: "rotated-access",
                refreshToken: "rotated-refresh",
                userId: "user-1",
                userEmail: "jane@example.com",
                userDisplayName: "Jane Doe",
                needsDisplayNameUpload: true
            )
        }
        let service = RemoteAuthenticationService(
            httpClient: UnusedHTTPClient(),
            keychainStore: keychain,
            usersService: usersService
        )
        var appleName = PersonNameComponents()
        appleName.givenName = "Jane"
        appleName.familyName = "Doe"

        _ = try await service.completeAppleSignIn(
            from: .sample(displayName: nil),
            appleFullName: appleName
        )

        #expect(keychain.stored?.accessToken == "rotated-access")
        #expect(keychain.stored?.refreshToken == "rotated-refresh")
        #expect(keychain.stored?.needsDisplayNameUpload == false)
        #expect(keychain.stored?.userDisplayName == AppleUserDisplayName.formatted(from: appleName))
    }

    @Test func storePublicUserIdBackfillsKeychainAndKeepsEverythingElse() async throws {
        let keychain = InMemoryKeychainStore()
        keychain.stored = StoredAuthData(
            accessToken: "access",
            refreshToken: "refresh",
            userId: "user-1",
            userEmail: "jane@example.com",
            userDisplayName: "Jane Doe",
            needsDisplayNameUpload: true
        )
        let service = RemoteAuthenticationService(
            httpClient: AuthHTTPClient { _ in .failure(.networkError) },
            keychainStore: keychain
        )

        try await service.storePublicUserId("JANEDOE123")

        #expect(keychain.stored?.userPublicId == "JANEDOE123")
        #expect(keychain.stored?.accessToken == "access")
        #expect(keychain.stored?.refreshToken == "refresh")
        #expect(keychain.stored?.userDisplayName == "Jane Doe")
        #expect(keychain.stored?.needsDisplayNameUpload == true)
    }

    @Test func storePublicUserIdDoesNothingWhenSignedOut() async throws {
        let keychain = InMemoryKeychainStore()
        let service = RemoteAuthenticationService(
            httpClient: AuthHTTPClient { _ in .failure(.networkError) },
            keychainStore: keychain
        )

        try await service.storePublicUserId("JANEDOE123")

        #expect(keychain.stored == nil)
    }

    @Test func restoreSessionKeepsPersistedDisplayNameAfterRefresh() async throws {
        let keychain = InMemoryKeychainStore()
        keychain.stored = StoredAuthData(
            accessToken: "old-access",
            refreshToken: "old-refresh",
            userId: "user-1",
            userEmail: "jane@example.com",
            userDisplayName: "Jane Doe",
            userPublicId: "JANEDOE123"
        )
        let client = AuthHTTPClient { _ in
            .success(Data(#"{"accessToken":"new-access","refreshToken":"new-refresh"}"#.utf8))
        }
        let service = RemoteAuthenticationService(
            httpClient: client,
            keychainStore: keychain
        )

        let session = try await service.restoreSession()

        #expect(session?.user.id == "user-1")
        #expect(session?.user.displayName == "Jane Doe")
        #expect(session?.user.email == "jane@example.com")
        #expect(session?.user.publicUserId == "JANEDOE123")
        #expect(keychain.stored?.accessToken == "new-access")
        #expect(keychain.stored?.userDisplayName == "Jane Doe")
        #expect(keychain.stored?.userPublicId == "JANEDOE123")
    }

    @Test func storedAuthDataDecodesLegacyPayloadWithoutDisplayName() throws {
        let json = Data("""
        {
          "accessToken": "a",
          "refreshToken": "r",
          "userId": "user-1",
          "userEmail": "a@b.com"
        }
        """.utf8)

        let stored = try JSONDecoder().decode(StoredAuthData.self, from: json)

        #expect(stored.userId == "user-1")
        #expect(stored.userEmail == "a@b.com")
        #expect(stored.userDisplayName == nil)
        #expect(stored.needsDisplayNameUpload == false)
    }

    @Test func authUserDTODecodesOptionalDisplayName() throws {
        let withName = Data("""
        {
          "accessToken": "a",
          "refreshToken": "r",
          "user": {
            "id": "user-1",
            "email": "a@b.com",
            "provider": "apple",
            "displayName": "Ada"
          }
        }
        """.utf8)
        let withoutName = Data("""
        {
          "accessToken": "a",
          "refreshToken": "r",
          "user": {
            "id": "user-1",
            "email": "a@b.com",
            "provider": "apple"
          }
        }
        """.utf8)

        let named = try JSONDecoder().decode(AuthAPIResponse.self, from: withName)
        let unnamed = try JSONDecoder().decode(AuthAPIResponse.self, from: withoutName)

        #expect(named.user.displayName == "Ada")
        #expect(unnamed.user.displayName == nil)
    }
}

private actor RecordingUsersService: UsersService {
    private(set) var updateCalls: [String] = []
    private var remoteDisplayName: String?
    private var updateError: UsersServiceError?
    private var onUpdate: (@Sendable () -> Void)?

    init(remoteDisplayName: String? = nil) {
        self.remoteDisplayName = remoteDisplayName
    }

    func setUpdateError(_ error: UsersServiceError?) {
        updateError = error
    }

    func setOnUpdate(_ handler: @escaping @Sendable () -> Void) {
        onUpdate = handler
    }

    func fetchMe(fallingBackTo currentUser: AuthenticatedUser) async throws -> AuthenticatedUser {
        currentUser
    }

    func fetchRemoteDisplayName() async throws -> String? {
        AppleUserDisplayName.nonBlank(remoteDisplayName)
    }

    func updateMe(
        displayName: String,
        fallingBackTo currentUser: AuthenticatedUser
    ) async throws -> AuthenticatedUser {
        if let updateError {
            throw updateError
        }
        onUpdate?()
        updateCalls.append(displayName)
        remoteDisplayName = displayName
        return AuthenticatedUser(
            id: currentUser.id,
            displayName: displayName,
            email: currentUser.email
        )
    }
}

private extension AuthAPIResponse {
    static func sample(displayName: String?) -> AuthAPIResponse {
        AuthAPIResponse(
            accessToken: "access",
            refreshToken: "refresh",
            user: AuthUserDTO(
                id: "user-1",
                email: "jane@example.com",
                provider: "apple",
                displayName: displayName,
                publicUserId: "JANEDOE123"
            )
        )
    }
}

private final class InMemoryKeychainStore: KeychainTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedData: StoredAuthData?

    var stored: StoredAuthData? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedData
        }
        set {
            lock.lock()
            storedData = newValue
            lock.unlock()
        }
    }

    func save(_ storedData: StoredAuthData) throws {
        stored = storedData
    }

    func getStoredAuthData() throws -> StoredAuthData? {
        stored
    }

    func deleteTokens() throws {
        stored = nil
    }
}

private struct UnusedHTTPClient: HTTPClient {
    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        throw HTTPClientError.networkError
    }
}

private struct AuthHTTPClient: HTTPClient {
    enum Outcome: Sendable {
        case success(Data)
        case failure(HTTPClientError)
    }

    private let handler: @Sendable (APIEndpoint) async -> Outcome

    init(handler: @escaping @Sendable (APIEndpoint) async -> Outcome) {
        self.handler = handler
    }

    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        switch await handler(endpoint) {
        case .success(let data):
            return try LiveHTTPClient.makeAPIDecoder().decode(T.self, from: data)
        case .failure(let error):
            throw error
        }
    }
}
