//
//  Chain.swift
//  toluWallet
//
//  One EVM network the wallet can read balances from and send on. The same
//  wallet address is valid on every one of them.
//

import Foundation

struct Chain: Identifiable, Hashable, Sendable {
    /// The EIP-155 chain id.
    let id: Int
    let name: String
    /// Native currency symbol (pays for gas).
    let symbol: String
    let rpcURL: String
    let explorerURL: String
    var isTestnet: Bool = false
    /// OP-stack chains charge an extra L1 data fee on top of gas.
    var hasL1DataFee: Bool = false
    /// A Blockscout instance that answers its REST API without a key. It is
    /// what lists every token, NFT and transaction; `nil` means this chain
    /// only shows the built-in tokens.
    var indexerURL: String?
    /// The chain's name on the price feed (DefiLlama). `nil` for testnets,
    /// whose assets have no price.
    var priceChain: String?
    /// The native coin's id on the price feed.
    var nativePriceKey: String?

    var hasIndexer: Bool { indexerURL != nil }

    func transactionURL(_ hash: String) -> URL? {
        URL(string: "\(explorerURL)/tx/\(hash)")
    }

    func addressURL(_ address: String) -> URL? {
        URL(string: "\(explorerURL)/address/\(address)")
    }
}
