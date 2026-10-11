//
//  ChainActivityModel.swift
//  toluWallet
//
//  A wallet's recent history on one chain, read from the chain's indexer.
//

import Foundation

@Observable
final class ChainActivityModel {

    let wallet: WalletRecord
    let chain: Chain

    private(set) var items: [ActivityItem] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var error: String?

    init(wallet: WalletRecord, chain: Chain) {
        self.wallet = wallet
        self.chain = chain
    }

    func load() async {
        guard chain.hasIndexer, !isLoading else { return }
        isLoading = true
        error = nil
        do {
            items = try await BlockscoutApi.activity(chain, address: wallet.address)
        } catch {
            self.error = "Couldn't load the history. Pull down to try again."
        }
        hasLoaded = true
        isLoading = false
    }
}
