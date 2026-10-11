//
//  ColdSetupPayload.swift
//  toluWallet
//
//  The record a toluCold device expects from the phone. The firmware's
//  `parseSetup` (tolu_cold/cold_target.h) reads exactly this — change
//  one side and change the other.
//
//      01 | key object id (4) | password object id (4) | n | password (n)
//

import Foundation

enum ColdSetupPayload {

    static let version: UInt8 = 0x01
    /// What the card's password object can hold.
    static let passwordLength = 4...16

    /// `nil` when the ids or password could not make a valid wallet — the
    /// device would refuse them too.
    static func make(keyObjectID: [UInt8], passwordObjectID: [UInt8], password: [UInt8]) -> Data? {
        guard keyObjectID.count == 4, passwordObjectID.count == 4,
              keyObjectID != passwordObjectID,
              keyObjectID != [0, 0, 0, 0], passwordObjectID != [0, 0, 0, 0],
              // 0x7FFFxxxx is the range NXP reserves for the card's own objects.
              Array(keyObjectID.prefix(2)) != [0x7F, 0xFF], Array(passwordObjectID.prefix(2)) != [0x7F, 0xFF],
              passwordLength.contains(password.count) else { return nil }
        return Data([version] + keyObjectID + passwordObjectID + [UInt8(password.count)] + password)
    }
}
