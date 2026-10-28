//
//  PublicKeyPointTests.swift
//  toluWalletTests
//
//  Only a secp256k1 public key may become a wallet: a key on another curve
//  would give an address that nothing can sign for.
//

import Foundation
import Testing
@testable import toluWallet

@MainActor
struct PublicKeyPointTests {

    private static let generator = "0479be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
        + "483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8"

    @Test func acceptsSecp256k1Keys() throws {
        #expect(Secp256k1.isOnCurve(try point(Self.generator)))
        // The key of the all-zero seed phrase (see SeedPhraseTests).
        #expect(Secp256k1.isOnCurve(try point(
            "0437b0bb7a8288d38ed49a524b5dc98cff3eb5ca824c9f9dc0dfdb3d9cd600f299"
            + "a6179912b7451c09896c4098eca7ce6b2e58330672795e847c4d6af44e024230"
        )))
    }

    @Test func rejectsTheP256Generator() throws {
        #expect(!Secp256k1.isOnCurve(try point(
            "046b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296"
            + "4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5"
        )))
    }

    @Test func rejectsMalformedPoints() throws {
        var moved = try point(Self.generator)
        moved[64] ^= 1
        #expect(!Secp256k1.isOnCurve(moved))

        var compressedPrefix = try point(Self.generator)
        compressedPrefix[0] = 0x02
        #expect(!Secp256k1.isOnCurve(compressedPrefix))

        // x = p is out of range even though it reduces to a small value.
        let outOfRange = try point("04" + "fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f"
            + String(repeating: "0", count: 64))
        #expect(!Secp256k1.isOnCurve(outOfRange))

        #expect(!Secp256k1.isOnCurve(Array(try point(Self.generator).dropLast())))
    }

    private func point(_ hex: String) throws -> [UInt8] {
        try #require(Hex.bytes(hex))
    }
}
