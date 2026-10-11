//
//  CardUid.swift
//  toluWallet
//
//  The card's factory unique id, normalized so values read by different code
//  paths (the async reader, the ported writer) compare equal. Two physical tags
//  can share an object id, so records are matched on (uniqueId + objectId).
//

import Foundation

enum CardUid {
    /// The SE05x unique id is 18 bytes.
    private static let hexDigits = 36

    /// The id as 36 uppercase hex digits. Returns nil for an empty value.
    ///
    /// The same id reaches the app in several shapes — bare, `0x`-prefixed and
    /// left-padded to 20 bytes, or with leftover TLV length bytes in front —
    /// so anything longer than 18 bytes is cut down to its trailing 18.
    static func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var s = raw
        if s.hasPrefix("0x") || s.hasPrefix("0X") { s = String(s.dropFirst(2)) }
        let cleaned = s.uppercased().filter { $0.isHexDigit }
        return cleaned.isEmpty ? nil : String(cleaned.suffix(hexDigits))
    }

    /// True when both ids are present and equal after normalization.
    static func sameCard(_ a: String?, _ b: String?) -> Bool {
        guard let a = normalize(a), let b = normalize(b) else { return false }
        return a == b
    }
}
