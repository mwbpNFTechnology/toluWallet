//
//  Tlv.swift
//  toluWallet
//
//  Minimal TLV (tag-length-value) build/parse for SE05x APDU payloads.
//

import Foundation

enum Tlv {
    /// Encodes a TLV with a single-byte length (values here are always short).
    static func encode(_ tag: UInt8, _ value: [UInt8]) -> [UInt8] {
        [tag, UInt8(value.count)] + value
    }

    /// Returns the value of the first top-level TLV with the given tag.
    /// Understands the ISO 7816 short form and the 0x81 / 0x82 length forms.
    static func findValue(_ bytes: [UInt8], tag: UInt8) -> [UInt8]? {
        var i = 0
        while i + 2 <= bytes.count {
            let currentTag = bytes[i]
            i += 1
            var length = Int(bytes[i])
            i += 1
            if length == 0x81 {
                if i >= bytes.count { break }
                length = Int(bytes[i]); i += 1
            } else if length == 0x82 {
                if i + 1 >= bytes.count { break }
                length = (Int(bytes[i]) << 8) | Int(bytes[i + 1]); i += 2
            }
            if i + length > bytes.count { break }
            if currentTag == tag { return Array(bytes[i..<i + length]) }
            i += length
        }
        return nil
    }
}
