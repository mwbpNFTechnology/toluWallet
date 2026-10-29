//
//  ColdSetupPayload.swift
//  toluWallet
//
//  The setup a toluCold device gets in `80 20 00 00`:
//
//    02                       format version
//    <key object id, 4>       where the secp256k1 key will live
//    <phone key object id, 4> where this iPhone's public key goes
//    <phone key, 65>          04 ‖ X ‖ Y on NIST P-256
//
//  Nothing in it is secret. The device writes the phone key as an ECKey
//  authentication object and binds the wallet key to it, so only this
//  iPhone — after Face ID — can ever use the key. tolu_cold/cold_target.h
//  parses the same record.
//

import Foundation

nonisolated enum ColdSetupPayload {

    static let version: UInt8 = 0x02

    /// `nil` when the ids or key could not make a valid wallet — the device
    /// would refuse them too.
    static func make(keyObjectID: [UInt8], phoneKeyObjectID: [UInt8], phoneKey: [UInt8]) -> Data? {
        guard keyObjectID.count == 4, phoneKeyObjectID.count == 4,
              keyObjectID != phoneKeyObjectID,
              keyObjectID != [0, 0, 0, 0], phoneKeyObjectID != [0, 0, 0, 0],
              // 0x7FFFxxxx is the range NXP reserves for the card's own objects.
              Array(keyObjectID.prefix(2)) != [0x7F, 0xFF], Array(phoneKeyObjectID.prefix(2)) != [0x7F, 0xFF],
              phoneKey.count == 65, phoneKey.first == 0x04 else { return nil }
        return Data([version] + keyObjectID + phoneKeyObjectID + phoneKey)
    }
}
