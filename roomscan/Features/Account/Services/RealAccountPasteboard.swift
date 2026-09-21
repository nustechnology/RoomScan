//
//  RealAccountPasteboard.swift
//  roomscan
//

import UIKit

/// Nonisolated so it can be a default argument; `copy` stays on the main actor for UIKit.
nonisolated struct RealAccountPasteboard: AccountPasteboard {
    @MainActor
    func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}
