//
//  NftCollection.swift
//  toluWallet
//
//  The tokens a wallet holds from one NFT contract (ERC-721 or ERC-1155).
//

import Foundation

struct NftCollection: Identifiable, Equatable {
    let chain: Chain
    let address: String
    let name: String
    /// "ERC-721" or "ERC-1155".
    let standard: String
    /// How many tokens of this collection the wallet holds.
    let count: Int
    /// Ids of the held tokens the indexer listed (it may list fewer than `count`).
    let tokenIds: [String]

    var id: String { "\(chain.id):\(address.lowercased())" }
}
