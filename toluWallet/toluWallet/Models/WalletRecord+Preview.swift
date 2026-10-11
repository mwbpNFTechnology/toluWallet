//
//  WalletRecord+Preview.swift
//  toluWallet
//
//  Sample data for SwiftUI previews. The address belongs to the well-known
//  test private key `1`; nothing real is stored here.
//

import Foundation

extension WalletRecord {
    static let preview = WalletRecord(
        label: "daily wallet",
        keyObjectID: "00000001",
        passwordObjectID: "00000002",
        password: "preview",
        publicKey: "0x0479be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8",
        address: "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf",
        cardUniqueId: "04005001A1B2C3D4E5F6000000000000ABCD",
        createdAt: Date(timeIntervalSince1970: 1_780_000_000)
    )
}
