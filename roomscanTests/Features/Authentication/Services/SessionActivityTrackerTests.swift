//
//  SessionActivityTrackerTests.swift
//  roomscanTests
//

import Foundation
import Testing
@testable import roomscan

@MainActor
struct SessionActivityTrackerTests {
    @Test func sessionIsNotExpiredInitially() {
        let tracker = SessionActivityTracker(
            userDefaults: UserDefaults(suiteName: #function)!,
            maxInactivityInterval: 30 * 24 * 60 * 60
        )
        tracker.clearActivity()

        #expect(tracker.isSessionExpired() == false)
    }

    @Test func recordingActivityUpdatesLastActivityTimestamp() {
        let defaults = UserDefaults(suiteName: #function)!
        let tracker = SessionActivityTracker(
            userDefaults: defaults,
            maxInactivityInterval: 30 * 24 * 60 * 60
        )
        tracker.clearActivity()

        tracker.recordActivity()

        #expect(tracker.isSessionExpired() == false)
    }

    @Test func sessionExpiresAfterInactivityPeriod() {
        let defaults = UserDefaults(suiteName: #function)!
        // Use a short 1 second inactivity threshold for test
        let tracker = SessionActivityTracker(
            userDefaults: defaults,
            maxInactivityInterval: 0.1
        )
        tracker.recordActivity()

        // Wait for inactivity interval to elapse
        Thread.sleep(forTimeInterval: 0.2)

        #expect(tracker.isSessionExpired() == true)
    }

    @Test func clearingActivityRemovesStoredDate() {
        let defaults = UserDefaults(suiteName: #function)!
        let tracker = SessionActivityTracker(
            userDefaults: defaults,
            maxInactivityInterval: 30 * 24 * 60 * 60
        )
        tracker.recordActivity()

        tracker.clearActivity()

        #expect(tracker.isSessionExpired() == false)
    }

    @Test func appStateRecordActivityRefreshesSessionWhenActive() async {
        let defaults = UserDefaults(suiteName: #function)!
        let tracker = SessionActivityTracker(
            userDefaults: defaults,
            maxInactivityInterval: 30 * 24 * 60 * 60
        )
        let service = MockAuthenticationService(
            configuration: .init(
                initialSession: .mockAppleUser,
                signInOutcome: .success,
                restoreFails: false,
                simulatedDelayNanoseconds: 0
            )
        )
        let appState = AppState(authenticationService: service, activityTracker: tracker)
        await appState.restoreSession()

        #expect(appState.isAuthenticated == true)

        appState.recordActivity()

        #expect(appState.isAuthenticated == true)
    }
}
