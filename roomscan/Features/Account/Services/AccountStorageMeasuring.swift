//
//  AccountStorageMeasuring.swift
//  roomscan
//

import Foundation

protocol AccountStorageMeasuring: Sendable {
    func usedBytes(forScanIDs scanIDs: [String]) async -> Int64
}
