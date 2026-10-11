//
//  KeyPairPayload.swift
//  toluWallet
//
//  The data of a WriteECKey command for a secp256k1 key pair that one auth
//  object (the password) guards. With no key values the tag generates the
//  pair itself; with both, it stores exactly that pair. The toluCold device
//  sends the same bytes (tolu_cold/cold_se05x.h).
//

import Foundation

enum KeyPairPayload {

    /// - Parameters:
    ///   - keyObjectID: the slot for the key pair (4 bytes).
    ///   - authObjectID: the object whose session may use the key (4 bytes).
    ///   - policyMask: what that session may do with it.
    ///   - key: a key pair to store as it is, or `nil` to have the tag make one.
    static func make(keyObjectID: [UInt8], authObjectID: [UInt8], policyMask: UInt32,
                     importing key: SeedPhraseKey? = nil) -> [UInt8] {
        // One policy rule: its length, who it is for, and what they may do.
        let mask: [UInt8] = [
            UInt8(truncatingIfNeeded: policyMask >> 24), UInt8(truncatingIfNeeded: policyMask >> 16),
            UInt8(truncatingIfNeeded: policyMask >> 8), UInt8(truncatingIfNeeded: policyMask)
        ]
        let rule = [UInt8(authObjectID.count + mask.count)] + authObjectID + mask

        var payload = Tlv.encode(Se05x.tagPolicy, rule)
            + Tlv.encode(Se05x.tag1, keyObjectID)
            + Tlv.encode(Se05x.tag2, [Se05x.curveIdSecp256k1])
        if let key {
            payload += Tlv.encode(Se05x.tag3, key.privateKey)
            payload += Tlv.encode(Se05x.tag4, key.publicKeyPoint)
        }
        return payload
    }
}
