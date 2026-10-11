//
//  EcdsaDer.swift
//  toluWallet
//
//  Parses the DER-encoded ECDSA signature the SE05x returns. Ported from
//  toluTag's EthereumSigner.
//

import Foundation

nonisolated enum EcdsaDer {

    /// Parses `SEQUENCE { INTEGER r, INTEGER s }`.
    static func parse(_ der: [UInt8]) -> (r: BigUInt, s: BigUInt)? {
        var offset = 0

        func readLength() -> Int? {
            guard offset < der.count else { return nil }
            let first = der[offset]; offset += 1
            if first < 0x80 { return Int(first) }
            let count = Int(first & 0x7F)
            guard count > 0, count <= 2, offset + count <= der.count else { return nil }
            var value = 0
            for _ in 0..<count { value = value << 8 | Int(der[offset]); offset += 1 }
            return value
        }

        func readInteger() -> BigUInt? {
            guard offset < der.count, der[offset] == 0x02 else { return nil }
            offset += 1
            guard let length = readLength(), offset + length <= der.count else { return nil }
            let value = BigUInt(bigEndian: Data(der[offset..<(offset + length)]))
            offset += length
            return value
        }

        guard !der.isEmpty, der[0] == 0x30 else { return nil }
        offset = 1
        guard readLength() != nil, let r = readInteger(), let s = readInteger() else { return nil }
        return (r, s)
    }
}
