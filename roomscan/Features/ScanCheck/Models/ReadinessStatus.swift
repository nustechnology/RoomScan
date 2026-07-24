//
//  ReadinessStatus.swift
//  roomscan
//

import Foundation

enum ReadinessStatus: Equatable {
    case checking
    case passed
    case failed(message: String, actionLabel: String?)
}
