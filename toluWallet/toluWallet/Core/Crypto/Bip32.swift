//
//  Bip32.swift
//  toluWallet
//
//  Seed → the wallet's private key (BIP-32 / BIP-44). Walks m/44'/60'/0'/0/0,
//  the path every Ethereum wallet uses for its first account — so a phrase
//  made here restores this exact address in MetaMask, Ledger, or anything
//  else. The same steps run on the toluCold device (tolu_cold/cold_bip32.h).
//

import CryptoKit
import Foundation

nonisolated enum Bip32 {

    static let hardened: UInt32 = 0x8000_0000

    /// m/44'/60'/0'/0/0
    static let ethereumPath: [UInt32] = [44 | hardened, 60 | hardened, 0 | hardened, 0, 0]

    /// The 32-byte private key at `path` for a 64-byte BIP-39 seed, or `nil`
    /// for the vanishingly rare seed BIP-32 says to skip.
    static func privateKey(seed: [UInt8], path: [UInt32] = ethereumPath) -> [UInt8]? {
        let master = hmac(key: Array("Bitcoin seed".utf8), data: seed)
        var key = Array(master[0..<32])
        var chain = Array(master[32..<64])

        let masterScalar = BigUInt(bigEndian: Data(key))
        guard !masterScalar.isZero, masterScalar < Secp256k1.n else { return nil }

        for index in path {
            guard let child = child(key: key, chain: chain, index: index) else { return nil }
            key = child.key
            chain = child.chain
        }
        return key
    }

    /// One step down the tree.
    private static func child(key: [UInt8], chain: [UInt8], index: UInt32) -> (key: [UInt8], chain: [UInt8])? {
        var data: [UInt8]
        if index & hardened != 0 {
            data = [0x00] + key
        } else {
            guard let point = Secp256k1.publicKeyPoint(privateKey: key),
                  let compressed = Secp256k1.compressed(point) else { return nil }
            data = compressed
        }
        data += [
            UInt8(truncatingIfNeeded: index >> 24), UInt8(truncatingIfNeeded: index >> 16),
            UInt8(truncatingIfNeeded: index >> 8), UInt8(truncatingIfNeeded: index)
        ]

        let digest = hmac(key: chain, data: data)
        let tweak = BigUInt(bigEndian: Data(digest[0..<32]))
        guard tweak < Secp256k1.n else { return nil }

        let childScalar = (tweak + BigUInt(bigEndian: Data(key))).modulo(Secp256k1.n)
        guard !childScalar.isZero, let bytes = childScalar.serialized(byteCount: 32) else { return nil }
        return ([UInt8](bytes), Array(digest[32..<64]))
    }

    private static func hmac(key: [UInt8], data: [UInt8]) -> [UInt8] {
        Array(HMAC<SHA512>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }
}
