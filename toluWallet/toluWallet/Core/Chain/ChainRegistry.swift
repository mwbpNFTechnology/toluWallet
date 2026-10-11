//
//  ChainRegistry.swift
//  toluWallet
//
//  The built-in networks, in ascending chain-id order (the wallet screen
//  re-orders them by value). RPC endpoints are public, key-less nodes. Each one
//  has to answer `eth_getTransactionReceipt`, which a transfer needs to
//  confirm: the publicnode endpoints for Optimism, BNB, Base and Arbitrum
//  refuse it without a token, so those chains use their official endpoints.
//
//  Indexers are the Blockscout instances that answer without a key. The ones
//  for Base, Arbitrum and Polygon turn away anything that isn't a browser,
//  and BNB and Avalanche have none, so those five chains have no indexer.
//

import Foundation

enum ChainRegistry {

    static let all: [Chain] = [
        Chain(id: 1, name: "Ethereum", symbol: "ETH",
              rpcURL: "https://ethereum-rpc.publicnode.com",
              explorerURL: "https://etherscan.io",
              indexerURL: "https://eth.blockscout.com",
              priceChain: "ethereum", nativePriceKey: "coingecko:ethereum"),
        Chain(id: 10, name: "Optimism", symbol: "ETH",
              rpcURL: "https://mainnet.optimism.io",
              explorerURL: "https://optimistic.etherscan.io",
              hasL1DataFee: true,
              indexerURL: "https://explorer.optimism.io",
              priceChain: "optimism", nativePriceKey: "coingecko:ethereum"),
        Chain(id: 56, name: "BNB Smart Chain", symbol: "BNB",
              rpcURL: "https://bsc-dataseed.bnbchain.org",
              explorerURL: "https://bscscan.com",
              priceChain: "bsc", nativePriceKey: "coingecko:binancecoin"),
        Chain(id: 137, name: "Polygon", symbol: "POL",
              rpcURL: "https://polygon-bor-rpc.publicnode.com",
              explorerURL: "https://polygonscan.com",
              priceChain: "polygon", nativePriceKey: "coingecko:polygon-ecosystem-token"),
        Chain(id: 8453, name: "Base", symbol: "ETH",
              rpcURL: "https://mainnet.base.org",
              explorerURL: "https://basescan.org",
              hasL1DataFee: true,
              priceChain: "base", nativePriceKey: "coingecko:ethereum"),
        Chain(id: 42_161, name: "Arbitrum One", symbol: "ETH",
              rpcURL: "https://arb1.arbitrum.io/rpc",
              explorerURL: "https://arbiscan.io",
              priceChain: "arbitrum", nativePriceKey: "coingecko:ethereum"),
        Chain(id: 43_114, name: "Avalanche C-Chain", symbol: "AVAX",
              rpcURL: "https://avalanche-c-chain-rpc.publicnode.com",
              explorerURL: "https://snowtrace.io",
              priceChain: "avax", nativePriceKey: "coingecko:avalanche-2"),
        Chain(id: 84_532, name: "Base Sepolia", symbol: "ETH",
              rpcURL: "https://base-sepolia-rpc.publicnode.com",
              explorerURL: "https://sepolia.basescan.org",
              isTestnet: true, hasL1DataFee: true,
              indexerURL: "https://base-sepolia.blockscout.com"),
        Chain(id: 11_155_111, name: "Sepolia", symbol: "ETH",
              rpcURL: "https://ethereum-sepolia-rpc.publicnode.com",
              explorerURL: "https://sepolia.etherscan.io",
              isTestnet: true,
              indexerURL: "https://eth-sepolia.blockscout.com")
    ].sorted { $0.id < $1.id }

    static func chain(id: Int) -> Chain? {
        all.first { $0.id == id }
    }
}
