//
//  ColdWalletDraft.swift
//  toluWallet
//
//  A cold-device wallet sent to the device but not yet checked against its
//  card. Nothing secret: the slots, and the label for the saved wallet.
//

import Foundation

struct ColdWalletDraft: Codable, Equatable, Sendable {
    let label: String
    /// 8 hex digits each, as they were sent to the device.
    let keyObjectID: String
    let phoneKeyObjectID: String
    let createdAt: Date
}
