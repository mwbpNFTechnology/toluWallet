//
//  EntropyMixer.swift
//  toluWallet
//
//  Two random sources into one. A seed phrase made on this phone starts from
//  a random number generated inside the tag's secure element. That number is
//  hashed together with one from the phone, so both generators would have to
//  be bad for the phrase to be weak — and the tag's bytes, which cross the air
//  unencrypted, are no use to anyone who caught them.
//
//  The toluCold device uses the same recipe and the same label
//  (tolu_cold/cold_entropy.h).
//

import CryptoKit
import Foundation
import Security

nonisolated enum EntropyMixer {

    /// How many bytes each source gives.
    static let sourceByteCount = 32

    private static let label = Array("tolu entropy v1".utf8)

    /// SHA-256(label || tag || phone), cut to `byteCount` (16 for 12 words).
    /// `nil` unless both sources are `sourceByteCount` long.
    static func mix(tag: [UInt8], phone: [UInt8], byteCount: Int) -> [UInt8]? {
        guard tag.count == sourceByteCount, phone.count == sourceByteCount,
              (1...SHA256.byteCount).contains(byteCount) else { return nil }
        var hasher = SHA256()
        hasher.update(data: label)
        hasher.update(data: tag)
        hasher.update(data: phone)
        return Array(hasher.finalize().prefix(byteCount))
    }

    /// Bytes from the system's secure generator, or `nil` if it failed.
    static func phoneRandom() -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: sourceByteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return status == errSecSuccess ? bytes : nil
    }
}
