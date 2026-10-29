//
//  PhoneKeyObjectTests.swift
//  toluWalletTests
//
//  The objects that bind a wallet key to an iPhone: the phone key written as
//  an authentication object, the wallet key's policy, and the curves. The
//  bytes are pinned here and in tolu_cold/test/test_card.cpp, so the app and
//  the device stay in step.
//

import CryptoKit
import Foundation
import Testing
@testable import toluWallet

@MainActor
struct PhoneKeyObjectTests {

    /// The NIST P-256 generator: a valid point, standing in for an iPhone's key.
    static let phoneKey = "046b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296"
        + "4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5"

    @Test func writesThePhoneKeyLikeTheFirmware() throws {
        let payload = PhoneKeyPayload.make(authObjectID: [0x12, 0x22, 0x22, 0x22],
                                           publicKey: try #require(Hex.bytes(Self.phoneKey)))
        #expect(Hex.string(payload) == "4104" + "12222222" + "420103" + "4441" + Self.phoneKey)
    }

    @Test func walletKeysMaySignVerifyAndReadOnly() {
        #expect(KeyPairPayload.walletPolicy == 0x1820_0000)
    }

    @Test func curvesAreWhatTheChipExpects() throws {
        for curve in [EcCurve.secp256k1, .nistP256] {
            #expect(curve.parameters.map(\.selector) == [0x10, 0x01, 0x02, 0x04, 0x08])
            #expect(curve.parameters.map(\.value.count) == [32, 32, 32, 65, 32])
        }
        #expect(EcCurve.secp256k1.id == 0x10)
        #expect(EcCurve.nistP256.id == 0x03)
        // CryptoKit rejects any point that is not on P-256.
        let generator = try #require(EcCurve.nistP256.parameters.first { $0.selector == 0x04 }?.value)
        #expect(throws: Never.self) { try P256.KeyAgreement.PublicKey(x963Representation: generator) }
        #expect(Hex.string(generator) == Self.phoneKey)
    }
}
