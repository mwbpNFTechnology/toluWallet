//
//  PriceApi.swift
//  toluWallet
//
//  US-dollar prices from DefiLlama's key-less coins API. A native coin is
//  asked for by its id (`coingecko:ethereum`), a token by `chain:address`.
//

import Foundation

enum PriceApi {

    /// The key a token is priced under.
    static func tokenKey(chain: String, address: String) -> String {
        "\(chain):\(address.lowercased())"
    }

    /// Prices for the given keys. Anything the feed doesn't know — or isn't
    /// confident about — is simply missing from the result.
    static func prices(_ keys: [String]) async -> [String: Double] {
        var result: [String: Double] = [:]
        // Keys travel in the URL path, so they go out in batches.
        for start in stride(from: 0, to: keys.count, by: 60) {
            let batch = Array(keys[start..<min(start + 60, keys.count)])
            for (key, price) in await fetch(batch) { result[key] = price }
        }
        return result
    }

    private static func fetch(_ keys: [String]) async -> [String: Double] {
        guard !keys.isEmpty,
              let url = URL(string: "https://coins.llama.fi/prices/current/" + keys.joined(separator: ",")) else {
            return [:]
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let coins = json["coins"] as? [String: [String: Any]] else {
            return [:]
        }

        var prices: [String: Double] = [:]
        for (key, coin) in coins {
            guard let price = coin["price"] as? Double, price > 0 else { continue }
            if let confidence = coin["confidence"] as? Double, confidence < 0.5 { continue }
            prices[key.lowercased()] = price
        }
        return prices
    }
}
