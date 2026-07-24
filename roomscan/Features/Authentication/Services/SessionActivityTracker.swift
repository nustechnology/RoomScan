//
//  SessionActivityTracker.swift
//  roomscan
//

import Foundation

@MainActor
final class SessionActivityTracker {
    private let userDefaults: UserDefaults
    private let key = "app.session.lastActivityDate"
    private let maxInactivityInterval: TimeInterval

    init(
        userDefaults: UserDefaults = .standard,
        maxInactivityInterval: TimeInterval = 30 * 24 * 60 * 60
    ) {
        self.userDefaults = userDefaults
        self.maxInactivityInterval = maxInactivityInterval
    }

    func recordActivity() {
        userDefaults.set(Date().timeIntervalSince1970, forKey: key)
    }

    func isSessionExpired() -> Bool {
        let lastActivityTimestamp = userDefaults.double(forKey: key)
        guard lastActivityTimestamp > 0 else {
            return false
        }
        let elapsed = Date().timeIntervalSince1970 - lastActivityTimestamp
        return elapsed > maxInactivityInterval
    }

    func clearActivity() {
        userDefaults.removeObject(forKey: key)
    }
}
