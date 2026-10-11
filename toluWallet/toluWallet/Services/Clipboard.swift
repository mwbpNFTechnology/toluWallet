//
//  Clipboard.swift
//  toluWallet
//
//  The system pasteboard, kept behind one small type.
//

import UIKit

enum Clipboard {
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }

    static var text: String? {
        UIPasteboard.general.string
    }
}
