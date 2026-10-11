//
//  TokenAmountTests.swift
//  toluWalletTests
//

import Testing
@testable import toluWallet

@MainActor
struct TokenAmountTests {

    private let oneAndAQuarterEther = BigUInt(1_250_000_000_000_000_000)

    @Test func parsesTypedAmounts() {
        #expect(TokenAmount.parse("1.25", decimals: 18) == oneAndAQuarterEther)
        #expect(TokenAmount.parse("1,25", decimals: 18) == oneAndAQuarterEther)
        #expect(TokenAmount.parse(".5", decimals: 6) == BigUInt(500_000))
        #expect(TokenAmount.parse("0", decimals: 6) == .zero)
    }

    @Test func rejectsWhatIsNotAnAmount() {
        #expect(TokenAmount.parse("", decimals: 6) == nil)
        #expect(TokenAmount.parse("abc", decimals: 6) == nil)
        #expect(TokenAmount.parse("1.2.3", decimals: 6) == nil)
        #expect(TokenAmount.parse("1.1234567", decimals: 6) == nil)
    }

    @Test func exactNeverRounds() {
        #expect(TokenAmount.exact(oneAndAQuarterEther, decimals: 18) == "1.25")
        #expect(TokenAmount.exact(BigUInt(1), decimals: 18) == "0.000000000000000001")
        #expect(TokenAmount.exact(.zero, decimals: 18) == "0")
        // MAX fills the field with this, so it has to parse back to the same balance.
        #expect(TokenAmount.parse(TokenAmount.exact(BigUInt(1), decimals: 18), decimals: 18) == BigUInt(1))
    }

    @Test func formatsForDisplay() {
        #expect(TokenAmount.format(oneAndAQuarterEther, decimals: 18) == "1.2500")
        #expect(TokenAmount.format(.zero, decimals: 18) == "0.0000")
        #expect(TokenAmount.format(BigUInt(7_000_000_000_000), decimals: 18) == "0.000007")
    }
}
