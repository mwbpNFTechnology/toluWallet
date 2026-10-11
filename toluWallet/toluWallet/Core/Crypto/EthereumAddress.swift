//
//  EthereumAddress.swift
//  toluWallet
//
//  Derives an Ethereum address from a secp256k1 public key point
//  (keccak256(X || Y), last 20 bytes), plus the EIP-55 checksum form and the
//  checks a recipient field needs.
//

import Foundation

enum EthereumAddress {

    /// - Parameter point: uncompressed public key (`0x04 || X || Y`, 65 bytes).
    /// - Returns: the `0x`-prefixed lower-case address, or `nil` if the point is invalid.
    static func from(publicKeyPoint point: [UInt8]) -> String? {
        guard point.count == 65, point[0] == 0x04 else { return nil }
        let xy = Array(point[1..<65])
        let hash = Keccak256.digest(xy)
        return "0x" + Hex.string(Array(hash[12..<32]))
    }

    /// The 20 address bytes, or `nil` if the text isn't a well-formed address.
    static func bytes(_ address: String) -> [UInt8]? {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count == 42, text.lowercased().hasPrefix("0x"),
              let bytes = Hex.bytes(text), bytes.count == 20 else { return nil }
        return bytes
    }

    /// The EIP-55 mixed-case checksum form. Returns the input unchanged if it
    /// isn't a well-formed address.
    static func checksummed(_ address: String) -> String {
        guard let bytes = bytes(address) else { return address }
        let lower = Hex.string(bytes)
        let hash = Hex.string(Keccak256.digest(Array(lower.utf8)))
        var out = "0x"
        for (character, nibble) in zip(lower, hash) {
            let raise = character.isLetter && (nibble.hexDigitValue ?? 0) >= 8
            out.append(raise ? Character(character.uppercased()) : character)
        }
        return out
    }

    /// True for a well-formed address. A mixed-case address must also carry a
    /// correct EIP-55 checksum, which catches a mistyped character.
    static func isValid(_ address: String) -> Bool {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard bytes(text) != nil else { return false }
        let body = text.dropFirst(2)
        let isSingleCase = body == body.lowercased() || body == body.uppercased()
        return isSingleCase || checksummed(text) == "0x\(body)"
    }

    /// The address in a scanned QR code, lower-case — or `nil` if the code
    /// isn't one. Accepts a bare address and the `ethereum:0x…` link form
    /// (with an optional `@chain` or `?query` after it).
    static func fromScanned(_ text: String) -> String? {
        var candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.lowercased().hasPrefix("ethereum:") { candidate = String(candidate.dropFirst(9)) }
        if let end = candidate.firstIndex(where: { $0 == "@" || $0 == "?" }) {
            candidate = String(candidate[..<end])
        }
        return isValid(candidate) ? candidate.lowercased() : nil
    }

    /// `0x12345678…abcd`, for tight rows.
    static func short(_ address: String) -> String {
        guard address.count > 14 else { return address }
        return address.prefix(8) + "…" + address.suffix(4)
    }
}
