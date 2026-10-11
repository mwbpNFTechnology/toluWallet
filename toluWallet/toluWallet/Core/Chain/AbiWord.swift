//
//  AbiWord.swift
//  toluWallet
//
//  32-byte ABI words for contract call data.
//

import Foundation

enum AbiWord {

    /// A 20-byte address, left-padded to 32 bytes.
    static func address(_ bytes: [UInt8]) -> [UInt8] {
        [UInt8](repeating: 0, count: max(0, 32 - bytes.count)) + bytes
    }

    /// An unsigned integer as a 32-byte big-endian word.
    static func uint(_ value: BigUInt) -> [UInt8] {
        guard let data = value.serialized(byteCount: 32) else {
            return [UInt8](repeating: 0xFF, count: 32)
        }
        return [UInt8](data)
    }

    static func uint(_ value: Int) -> [UInt8] {
        uint(BigUInt(UInt64(max(0, value))))
    }
}
