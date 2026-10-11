//
//  OpStackOracle.swift
//  toluWallet
//
//  Call data for the OP-stack GasPriceOracle, which prices the L1 data fee
//  that Optimism and Base add on top of gas.
//

import Foundation

enum OpStackOracle {

    /// `getL1Fee(bytes)` — selector 0x49948e0e.
    static func getL1Fee(_ transaction: [UInt8]) -> [UInt8] {
        let padding = (32 - transaction.count % 32) % 32
        return [0x49, 0x94, 0x8E, 0x0E]
            + AbiWord.uint(32)                      // offset of the bytes argument
            + AbiWord.uint(transaction.count)
            + transaction
            + [UInt8](repeating: 0, count: padding)
    }
}
