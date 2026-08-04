//
//  AccountStorageMeasuring.swift
//  roomscan
//

import Foundation

protocol AccountStorageMeasuring: Sendable {
    func usedBytes() async -> Int64
}
