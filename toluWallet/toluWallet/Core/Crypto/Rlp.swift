//
//  Rlp.swift
//  toluWallet
//
//  Recursive Length Prefix encoding — the serialization Ethereum transactions
//  are signed and broadcast in.
//

import Foundation

enum Rlp {

    /// Encodes a byte string.
    static func encode(_ bytes: [UInt8]) -> [UInt8] {
        if bytes.count == 1, bytes[0] < 0x80 { return bytes }
        return lengthPrefix(bytes.count, offset: 0x80) + bytes
    }

    /// Encodes an integer (big-endian, no leading zeros; zero is the empty string).
    static func encode(_ value: BigUInt) -> [UInt8] {
        encode(value.minimalBytes)
    }

    /// Wraps already-encoded items in a list.
    static func list(_ items: [[UInt8]]) -> [UInt8] {
        let payload = items.flatMap { $0 }
        return lengthPrefix(payload.count, offset: 0xC0) + payload
    }

    private static func lengthPrefix(_ length: Int, offset: UInt8) -> [UInt8] {
        if length <= 55 { return [offset + UInt8(length)] }
        var lengthBytes: [UInt8] = []
        var remaining = length
        while remaining > 0 {
            lengthBytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        }
        return [offset + 55 + UInt8(lengthBytes.count)] + lengthBytes
    }
}
