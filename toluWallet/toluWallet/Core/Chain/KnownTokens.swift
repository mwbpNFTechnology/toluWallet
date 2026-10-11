//
//  KnownTokens.swift
//  toluWallet
//
//  The ERC-20 tokens checked on each chain. Extends the list tolu's vault uses.
//

import Foundation

enum KnownTokens {

    static func forChain(_ chainId: Int) -> [KnownToken] {
        switch chainId {
        case 1:
            return [
                KnownToken(symbol: "USDC", name: "USD Coin", address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", decimals: 6),
                KnownToken(symbol: "USDT", name: "Tether USD", address: "0xdAC17F958D2ee523a2206206994597C13D831ec7", decimals: 6),
                KnownToken(symbol: "DAI", name: "Dai", address: "0x6B175474E89094C44Da98b954EedeAC495271d0F", decimals: 18),
                KnownToken(symbol: "WETH", name: "Wrapped Ether", address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", decimals: 18)
            ]
        case 10:
            return [
                KnownToken(symbol: "USDC", name: "USD Coin", address: "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85", decimals: 6),
                KnownToken(symbol: "USDT", name: "Tether USD", address: "0x94b008aA00579c1307B0EF2c499aD98a8ce58e58", decimals: 6)
            ]
        case 56:
            return [
                KnownToken(symbol: "USDC", name: "USD Coin", address: "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d", decimals: 18),
                KnownToken(symbol: "USDT", name: "Tether USD", address: "0x55d398326f99059fF775485246999027B3197955", decimals: 18)
            ]
        case 137:
            return [
                KnownToken(symbol: "USDC", name: "USD Coin", address: "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359", decimals: 6),
                KnownToken(symbol: "USDT", name: "Tether USD", address: "0xc2132D05D31c914a87C6611C10748AEb04B58e8F", decimals: 6)
            ]
        case 8453:
            return [
                KnownToken(symbol: "USDC", name: "USD Coin", address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", decimals: 6)
            ]
        case 42_161:
            return [
                KnownToken(symbol: "USDC", name: "USD Coin", address: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831", decimals: 6),
                KnownToken(symbol: "USDT", name: "Tether USD", address: "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9", decimals: 6)
            ]
        case 43_114:
            return [
                KnownToken(symbol: "USDC", name: "USD Coin", address: "0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E", decimals: 6)
            ]
        case 84_532:
            return [
                KnownToken(symbol: "USDC", name: "USD Coin (Circle test)", address: "0x036CbD53842c5426634e7929541eC2318f3dCF7e", decimals: 6)
            ]
        case 11_155_111:
            return [
                KnownToken(symbol: "USDC", name: "USD Coin (Circle test)", address: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238", decimals: 6)
            ]
        default:
            return []
        }
    }
}
