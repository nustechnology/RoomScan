//
//  AccountStorageMeasuring.swift
//  roomscan
//

import Foundation

nonisolated protocol AccountStorageMeasuring: Sendable {
    func usedBytes(forScanIDs scanIDs: [String]) async -> Int64
}
