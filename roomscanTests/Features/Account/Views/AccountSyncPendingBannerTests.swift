//
//  AccountSyncPendingBannerTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

struct AccountSyncPendingBannerTests {
    @Test func pendingBodyUsesSingularAndPluralForms() {
        #expect(pendingBody(count: 0) == "0 scans are still uploading.")
        #expect(pendingBody(count: 1) == "1 scan is still uploading.")
        #expect(pendingBody(count: 2) == "2 scans are still uploading.")
    }

    private func pendingBody(count: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "account.sync.pending.body"),
            count
        )
    }
}
