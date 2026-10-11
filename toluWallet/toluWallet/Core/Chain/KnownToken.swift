//
//  KnownToken.swift
//  toluWallet
//
//  An ERC-20 token the wallet checks a balance for.
//

import Foundation

struct KnownToken: Identifiable, Hashable, Sendable {
    let symbol: String
    let name: String
    let address: String
    let decimals: Int

    var id: String { address.lowercased() }
}
