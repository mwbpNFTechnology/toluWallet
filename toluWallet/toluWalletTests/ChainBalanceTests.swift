//
//  ChainBalanceTests.swift
//  toluWalletTests
//

import Testing
@testable import toluWallet

@MainActor
struct ChainBalanceTests {

    private let ethereum = ChainRegistry.all[0]

    @Test func notEmptyUntilTheChainHasAnswered() {
        #expect(!ChainBalance(isLoading: true).isEmpty)
        #expect(ChainBalance(native: .zero).isEmpty)
    }

    @Test func partialAnswerIsNeverEmpty() {
        #expect(!ChainBalance(native: .zero, isPartial: true).isEmpty)
    }

    @Test func anythingHeldMakesItNotEmpty() {
        #expect(!ChainBalance(native: BigUInt(1)).isEmpty)

        let token = Holding(chain: ethereum, token: KnownTokens.forChain(1)[0], balance: BigUInt(1))
        #expect(!ChainBalance(native: .zero, tokens: [token]).isEmpty)

        let nft = NftCollection(chain: ethereum, address: "0x0000000000000000000000000000000000000001",
                                name: "n", standard: "ERC-721", count: 1, tokenIds: ["7"])
        #expect(!ChainBalance(native: .zero, nfts: [nft]).isEmpty)
    }

    @Test func valueAddsNativeCoinAndPricedTokens() {
        // 2 ETH at $2,500 plus 25 USDC at $1; an unpriced token adds nothing.
        let usdc = Holding(chain: ethereum, token: KnownTokens.forChain(1)[0], balance: BigUInt(25_000_000), usdPrice: 1)
        let unpriced = Holding(chain: ethereum, token: KnownTokens.forChain(1)[2], balance: BigUInt(5))
        let balance = ChainBalance(native: BigUInt(2_000_000_000_000_000_000), nativeUsdPrice: 2500,
                                   tokens: [usdc, unpriced])
        #expect(balance.usdValue == 5025)
        #expect(ChainBalance(native: BigUInt(2_000_000_000_000_000_000)).usdValue == 0)
    }
}
