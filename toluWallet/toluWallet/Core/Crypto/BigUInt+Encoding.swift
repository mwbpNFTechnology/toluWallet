//
//  BigUInt+Encoding.swift
//  toluWallet
//
//  The conversions a wallet needs on top of the recovery arithmetic: minimal
//  big-endian bytes (RLP), JSON-RPC hex quantities, decimal strings for
//  amounts, and division by a small value.
//

import Foundation

nonisolated extension BigUInt {

    /// Big-endian bytes with no leading zeros; empty for zero. This is the form
    /// RLP expects for an integer.
    var minimalBytes: [UInt8] {
        guard !isZero else { return [] }
        guard let data = serialized(byteCount: (bitWidth + 7) / 8) else { return [] }
        return [UInt8](data)
    }

    /// A JSON-RPC quantity: `0x`-prefixed hex with no leading zeros (`0x0` for zero).
    var hexQuantity: String {
        guard !isZero else { return "0x0" }
        let hex = Hex.string(minimalBytes)
        return "0x" + (hex.hasPrefix("0") ? String(hex.dropFirst()) : hex)
    }

    /// Base-10 digits, as balances and amounts are shown.
    var decimalString: String {
        guard !isZero else { return "0" }
        var chunks: [String] = []
        var value = self
        while !value.isZero {
            let (quotient, remainder) = value.dividedBy(1_000_000_000)
            chunks.append(String(remainder))
            value = quotient
        }
        var text = chunks.removeLast()
        for chunk in chunks.reversed() {
            text += String(repeating: "0", count: 9 - chunk.count) + chunk
        }
        return text
    }

    /// Quotient and remainder of dividing by a small value.
    func dividedBy(_ divisor: UInt32) -> (quotient: BigUInt, remainder: UInt32) {
        precondition(divisor != 0, "division by zero")
        var quotient = [UInt32](repeating: 0, count: limbs.count)
        var remainder: UInt64 = 0
        for index in stride(from: limbs.count - 1, through: 0, by: -1) {
            let current = (remainder << 32) | UInt64(limbs[index])
            quotient[index] = UInt32(current / UInt64(divisor))
            remainder = current % UInt64(divisor)
        }
        return (BigUInt(limbs: quotient), UInt32(remainder))
    }

    /// `self * numerator / denominator`, rounded down — for fee buffers.
    func scaled(by numerator: UInt32, over denominator: UInt32) -> BigUInt {
        (self * BigUInt(UInt64(numerator))).dividedBy(denominator).quotient
    }
}
