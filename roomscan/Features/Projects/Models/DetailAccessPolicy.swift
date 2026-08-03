//
//  DetailAccessPolicy.swift
//  roomscan
//

import Foundation

enum DetailAccessPolicy: Equatable, Sendable {
    case editable
    case readOnly

    var allowsOwnerActions: Bool { self == .editable }
}
