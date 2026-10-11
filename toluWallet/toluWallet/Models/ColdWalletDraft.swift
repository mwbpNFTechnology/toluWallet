//
//  ColdWalletDraft.swift
//  toluWallet
//
//  The details of a cold-device wallet between "sent to the device" and
//  "checked against the card". The device needs minutes — a seed phrase is
//  being written down — and the app will have locked by the time it is done.
//

import Foundation

struct ColdWalletDraft: Codable, Equatable, Sendable {
    let label: String
    /// 8 hex digits each, as they were sent to the device.
    let keyObjectID: String
    let passwordObjectID: String
    let password: String
    let createdAt: Date
}
