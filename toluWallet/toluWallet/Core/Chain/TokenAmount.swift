//
//  TokenAmount.swift
//  toluWallet
//
//  Converts between base units (wei and friends) and the decimal amounts a
//  person reads and types. Works on digit strings, so nothing is ever rounded
//  through a floating-point number. Ported from tolu's vault helpers.
//

import Foundation

enum TokenAmount {

    /// A typed amount → base units. `nil` if it isn't a number or has more
    /// fraction digits than the asset supports.
    static func parse(_ amount: String, decimals: Int) -> BigUInt? {
        let text = amount.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !text.isEmpty, text != "." else { return nil }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }

        let whole = parts[0].isEmpty ? "0" : String(parts[0])
        var fraction = parts.count == 2 ? String(parts[1]) : ""
        guard whole.allSatisfy(\.isAsciiDigit), fraction.allSatisfy(\.isAsciiDigit) else { return nil }
        guard fraction.count <= decimals else { return nil }

        fraction += String(repeating: "0", count: decimals - fraction.count)
        return BigUInt(decimalString: whole + fraction)
    }

    /// Base units → the exact amount, digit for digit, with no trailing zeros.
    /// `format` is for display and truncates; this never does, so MAX can't
    /// ask for a hair more than the wallet holds.
    static func exact(_ raw: BigUInt, decimals: Int) -> String {
        let digits = raw.decimalString
        guard decimals > 0 else { return digits }

        let padded = String(repeating: "0", count: max(0, decimals + 1 - digits.count)) + digits
        let split = padded.index(padded.endIndex, offsetBy: -decimals)
        let whole = String(padded[..<split])
        var fraction = String(padded[split...])
        while fraction.hasSuffix("0") { fraction.removeLast() }
        return fraction.isEmpty ? whole : "\(whole).\(fraction)"
    }

    /// Base units → a short display amount with `places` fraction digits.
    static func format(_ raw: BigUInt, decimals: Int, places: Int = 4) -> String {
        let parts = exact(raw, decimals: decimals).split(separator: ".", omittingEmptySubsequences: false)
        let whole = String(parts[0])
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard places > 0, decimals > 0 else { return whole }

        // Small but real: 0.000007 ETH should not render as 0.0000.
        var width = places
        if whole == "0", let firstDigit = fraction.firstIndex(where: { $0 != "0" }) {
            let position = fraction.distance(from: fraction.startIndex, to: firstDigit) + 1
            width = max(places, min(position, decimals))
        }

        let cut = String(fraction.prefix(width))
        return whole + "." + cut + String(repeating: "0", count: max(0, width - cut.count))
    }
}

private extension Character {
    var isAsciiDigit: Bool { isASCII && isNumber }
}
