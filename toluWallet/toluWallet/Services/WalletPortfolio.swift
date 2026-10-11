//
//  WalletPortfolio.swift
//  toluWallet
//
//  Everything one wallet holds, chain by chain: the native coin, tokens, NFTs
//  and what it is all worth. Chains are read in parallel and each fills in as
//  it answers. Shared by the wallet screen and the chain screens, so opening a
//  chain doesn't read it again.
//

import Foundation

@Observable
final class WalletPortfolio {

    let wallet: WalletRecord
    let chains = ChainRegistry.all

    private(set) var balances: [Int: ChainBalance] = [:]
    private(set) var isLoading = false

    @ObservationIgnored private var loadedAt: Date?
    /// Native coin prices from the last load, so a single-chain refresh can reuse them.
    @ObservationIgnored private var nativePrices: [String: Double] = [:]

    init(wallet: WalletRecord) {
        self.wallet = wallet
    }

    // MARK: - Reading

    func balance(for chain: Chain) -> ChainBalance {
        balances[chain.id] ?? ChainBalance(isLoading: true)
    }

    /// Most valuable first. Chains worth the same (testnets, mostly) put the
    /// ones holding something ahead of the empty ones, then go by chain id.
    var sortedChains: [Chain] {
        chains.sorted { first, second in
            let a = balance(for: first), b = balance(for: second)
            if a.usdValue != b.usdValue { return a.usdValue > b.usdValue }
            let aHolds = a.isLoaded && !a.isEmpty, bHolds = b.isLoaded && !b.isEmpty
            if aHolds != bHolds { return aHolds }
            return first.id < second.id
        }
    }

    var totalUsd: Double {
        balances.values.reduce(0) { $0 + $1.usdValue }
    }

    /// What can be sent from one chain: the native coin, then tokens by value.
    func holdings(on chain: Chain) -> [Holding] {
        guard let balance = balances[chain.id] else { return [] }
        var list: [Holding] = []
        if let native = balance.native, !native.isZero {
            list.append(Holding(chain: chain, token: nil, balance: native, usdPrice: balance.nativeUsdPrice))
        }
        return list + balance.tokens
    }

    /// Everything that can be sent, in the same chain order as the wallet screen.
    var holdings: [Holding] {
        sortedChains.flatMap { holdings(on: $0) }
    }

    // MARK: - Loading

    /// Loads on first use, and again once what is shown is a minute old.
    func loadIfStale() async {
        if let loadedAt, Date.now.timeIntervalSince(loadedAt) < 60 { return }
        await load()
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        loadedAt = .now

        // Native prices don't depend on balances, so they are asked for alongside.
        async let prices = PriceApi.prices(Array(Set(chains.compactMap(\.nativePriceKey))))
        await withTaskGroup(of: Void.self) { group in
            for chain in chains {
                group.addTask { await self.read(chain) }
            }
        }
        nativePrices = await prices
        for chain in chains { applyNativePrice(chain) }
        await priceTokens(on: chains)

        isLoading = false
    }

    /// Refreshes a single chain — after a transfer, or a pull on its screen.
    func load(_ chain: Chain) async {
        await read(chain)
        applyNativePrice(chain)
        await priceTokens(on: [chain])
    }

    private func read(_ chain: Chain) async {
        var state = balances[chain.id] ?? ChainBalance()
        state.isLoading = true
        state.error = nil
        balances[chain.id] = state

        do {
            async let native = EvmRpc.nativeBalance(chain, address: wallet.address)

            var tokens: [Holding] = []
            var nfts: [NftCollection] = []
            var isPartial = false
            if chain.hasIndexer, let listed = try? await BlockscoutApi.tokenHoldings(chain, address: wallet.address) {
                tokens = listed
                nfts = (try? await BlockscoutApi.nftCollections(chain, address: wallet.address)) ?? []
            } else {
                // No indexer here, or it didn't answer: ask the built-in
                // token contracts directly, so balances still show.
                tokens = await knownTokenHoldings(on: chain)
                isPartial = chain.hasIndexer
            }

            state.native = try await native
            state.tokens = tokens
            state.nfts = nfts
            state.isPartial = isPartial
        } catch {
            state.error = "couldn't reach \(chain.name)"
        }

        state.isLoading = false
        balances[chain.id] = state
    }

    private func knownTokenHoldings(on chain: Chain) async -> [Holding] {
        var holdings: [Holding] = []
        for token in KnownTokens.forChain(chain.id) {
            // One token failing to answer shouldn't hide the rest of the chain.
            guard let amount = try? await EvmRpc.tokenBalance(chain, token: token.address, holder: wallet.address),
                  !amount.isZero else { continue }
            holdings.append(Holding(chain: chain, token: token, balance: amount))
        }
        return holdings
    }

    // MARK: - Prices

    private func applyNativePrice(_ chain: Chain) {
        guard let key = chain.nativePriceKey, let price = nativePrices[key.lowercased()] else { return }
        balances[chain.id]?.nativeUsdPrice = price
    }

    /// Fills in prices the indexer didn't supply, then orders each chain's
    /// tokens by value. Tokens the feed doesn't know stay unpriced — which is
    /// also what happens to worthless airdrops.
    private func priceTokens(on chains: [Chain]) async {
        var keys: [String] = []
        for chain in chains {
            guard let priceChain = chain.priceChain else { continue }
            for holding in balances[chain.id]?.tokens ?? [] where holding.usdPrice == nil {
                if let token = holding.token {
                    keys.append(PriceApi.tokenKey(chain: priceChain, address: token.address))
                }
            }
        }
        let prices = keys.isEmpty ? [:] : await PriceApi.prices(keys)

        for chain in chains {
            guard var state = balances[chain.id] else { continue }
            if let priceChain = chain.priceChain {
                for index in state.tokens.indices where state.tokens[index].usdPrice == nil {
                    guard let token = state.tokens[index].token else { continue }
                    state.tokens[index].usdPrice = prices[PriceApi.tokenKey(chain: priceChain, address: token.address)]
                }
            }
            // Priced tokens by value, then the built-in ones, then the rest —
            // so a real token isn't buried under unpriced airdrops.
            let builtIn = Set(KnownTokens.forChain(chain.id).map(\.id))
            func rank(_ holding: Holding) -> Int {
                if holding.usdValue != nil { return 0 }
                return builtIn.contains(holding.token?.id ?? "") ? 1 : 2
            }
            state.tokens.sort { first, second in
                let a = rank(first), b = rank(second)
                if a != b { return a < b }
                let x = first.usdValue ?? 0, y = second.usdValue ?? 0
                return x != y ? x > y : first.symbol.lowercased() < second.symbol.lowercased()
            }
            balances[chain.id] = state
        }
    }
}
