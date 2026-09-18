//
//  RealAccountPasteboard.swift
//  roomscan
//

import UIKit

struct RealAccountPasteboard: AccountPasteboard {
    func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}
