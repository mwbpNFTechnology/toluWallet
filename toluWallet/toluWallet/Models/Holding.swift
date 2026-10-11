//
//  Holding.swift
//  toluWallet
//
//  One fungible asset the wallet holds on one chain: the chain's native coin,
//  or an ERC-20 token.
//

import Foundation

struct Holding: Identifiable, Equatable {
    let chain: Chain
    /// `nil` for the chain's native coin.
    let token: KnownToken?
    /// Balance in base units.
    let balance: BigUInt
    /// Price of one whole unit in US dollars, when the price feed knows it.
    var usdPrice: Double?

    var id: String { "\(chain.id):\(token?.id ?? "native")" }
    var isNative: Bool { token == nil }
    var symbol: String { token?.symbol ?? chain.symbol }
    var name: String { token?.name ?? chain.name }
    var decimals: Int { token?.decimals ?? 18 }

    var balanceText: String { TokenAmount.format(balance, decimals: decimals) }

    /// What the balance is worth, or `nil` when the asset has no price.
    var usdValue: Double? {
        guard let usdPrice, let amount = Double(TokenAmount.exact(balance, decimals: decimals)) else { return nil }
        return amount * usdPrice
    }
}
