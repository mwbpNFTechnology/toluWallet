//
//  Secp256k1+Keys.swift
//  toluWallet
//
//  Private key → public key, for a wallet made from a seed phrase on this
//  phone. Like the rest of the curve code this is not constant-time. That is
//  accepted here because it runs once, on the owner's phone, with nobody
//  placed to time it — it is not a signing service. Every signature after
//  that is made by the tag.
//

import Foundation

nonisolated extension Secp256k1 {

    /// The uncompressed public key (`0x04 || X || Y`, 65 bytes) of a 32-byte
    /// private key, or `nil` if the key is zero or not below the group order.
    static func publicKeyPoint(privateKey: [UInt8]) -> [UInt8]? {
        guard privateKey.count == 32 else { return nil }
        let scalar = BigUInt(bigEndian: Data(privateKey))
        guard !scalar.isZero, scalar < n,
              let (x, y) = toAffine(multiply(generator, by: scalar)),
              let xBytes = x.serialized(byteCount: 32),
              let yBytes = y.serialized(byteCount: 32)
        else { return nil }

        var point: [UInt8] = [0x04]
        point += xBytes
        point += yBytes
        return point
    }

    /// The 33-byte compressed form of an uncompressed point.
    static func compressed(_ point: [UInt8]) -> [UInt8]? {
        guard point.count == 65, point[0] == 0x04 else { return nil }
        return [point[64] & 1 == 1 ? 0x03 : 0x02] + point[1..<33]
    }
}
