//
//  CardUidTests.swift
//  toluWalletTests
//

import Testing
@testable import toluWallet

@MainActor
struct CardUidTests {

    private let uid = "04005001A1B2C3D4E5F60718293A4B5C6D7E"

    @Test func everyShapeOfTheSameIdNormalizesAlike() {
        // bare 18 bytes
        #expect(CardUid.normalize(uid) == uid)
        // 0x-prefixed, lower-case, left-padded to 20 bytes
        #expect(CardUid.normalize("0x0000" + uid.lowercased()) == uid)
        // two leftover TLV length bytes in front
        #expect(CardUid.normalize("0012" + uid) == uid)
        #expect(CardUid.sameCard("0012" + uid, "0x0000" + uid.lowercased()))
    }

    @Test func differentCardsDoNotMatch() {
        #expect(!CardUid.sameCard(uid, "04005001A1B2C3D4E5F60718293A4B5C6D7F"))
    }

    @Test func missingIdNeverMatches() {
        #expect(CardUid.normalize(nil) == nil)
        #expect(CardUid.normalize("0x") == nil)
        #expect(!CardUid.sameCard(nil, uid))
    }
}
