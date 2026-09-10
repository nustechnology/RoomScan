//
//  MockAccountStorageMeasuring.swift
//  roomscan
//

import Foundation

nonisolated struct MockAccountStorageMeasuring: AccountStorageMeasuring {
    /// ~1.8 GB to match the Account design mock.
    static let defaultUsedBytes: Int64 = 1_932_735_283

    let usedBytesValue: Int64

    init(usedBytesValue: Int64 = Self.defaultUsedBytes) {
        self.usedBytesValue = usedBytesValue
    }

    func usedBytes(forScanIDs scanIDs: [String]) async -> Int64 {
        usedBytesValue
    }
}
