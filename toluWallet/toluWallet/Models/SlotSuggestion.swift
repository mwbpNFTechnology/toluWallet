//
//  SlotSuggestion.swift
//  toluWallet
//
//  Object-id arithmetic for the create screens: a wallet takes two slots on
//  the card, and the password slot defaults to the one after the key slot.
//

import Foundation

enum SlotSuggestion {

    /// The first slot past everything `used`, as 8 hex digits.
    static func firstFree(after used: [UInt32]) -> String {
        text((used.max() ?? 0) &+ 1)
    }

    /// The slot after a complete 8-digit one; `nil` while it is still being typed.
    static func next(after slot: String) -> String? {
        guard slot.count == 8, let value = UInt32(slot, radix: 16) else { return nil }
        return text(value &+ 1)
    }

    private static func text(_ value: UInt32) -> String {
        let hex = String(value, radix: 16)
        return String(repeating: "0", count: 8 - hex.count) + hex
    }
}
