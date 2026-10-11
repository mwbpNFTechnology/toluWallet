//
//  ChainBalance.swift
//  toluWallet
//
//  What is known about a wallet's assets on one chain right now.
//

import Foundation

struct ChainBalance: Equatable {
    /// Native coin balance; `nil` until the first answer arrives.
    var native: BigUInt?
    /// Price of the native coin in US dollars; `nil` on testnets.
    var nativeUsdPrice: Double?
    /// ERC-20 tokens with a non-zero balance.
    var tokens: [Holding] = []
    var nfts: [NftCollection] = []
    /// True when the chain's indexer didn't answer, so only the built-in
    /// tokens could be checked and anything else the wallet holds is missing.
    var isPartial = false
    var isLoading = false
    var error: String?

    var isLoaded: Bool { native != nil }

    var nftCount: Int { nfts.reduce(0) { $0 + $1.count } }

    /// True once the chain has answered in full and the wallet holds nothing
    /// on it. A partial answer can't prove that, so it never counts as empty.
    var isEmpty: Bool {
        guard let native, !isPartial else { return false }
        return native.isZero && tokens.isEmpty && nfts.isEmpty
    }

    /// Everything priced on this chain, in US dollars. NFTs aren't valued.
    var usdValue: Double {
        var total = tokens.reduce(0) { $0 + ($1.usdValue ?? 0) }
        if let native, let nativeUsdPrice, let amount = Double(TokenAmount.exact(native, decimals: 18)) {
            total += amount * nativeUsdPrice
        }
        return total
    }
}
