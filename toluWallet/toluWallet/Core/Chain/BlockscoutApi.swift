//
//  BlockscoutApi.swift
//  toluWallet
//
//  Reads what a plain RPC node can't answer — every token and NFT an address
//  holds, and its history — from a chain's Blockscout indexer. Only the first
//  page of each list is read (50 entries), which is plenty for a wallet screen.
//  An address that has been around collects airdropped junk; tokens the
//  indexer flags as scams are dropped, the rest are shown and sorted last.
//

import Foundation

enum BlockscoutApi {

    /// How many history lines a chain screen shows.
    private static let maxEntries = 50

    /// ERC-20 tokens with a non-zero balance. Tokens the indexer marks as
    /// scams, or that don't declare a symbol and decimals, are left out.
    static func tokenHoldings(_ chain: Chain, address: String) async throws -> [Holding] {
        let items = try await list(chain, path: "addresses/\(address)/tokens?type=ERC-20")
        return items.compactMap { item in
            guard let token = item["token"] as? [String: Any],
                  token["reputation"] as? String != "scam",
                  let contract = token["address_hash"] as? String,
                  let symbol = (token["symbol"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !symbol.isEmpty,
                  let decimals = (token["decimals"] as? String).flatMap({ Int($0) }),
                  (0...36).contains(decimals),
                  let balance = (item["value"] as? String).flatMap({ BigUInt(decimalString: $0) }),
                  !balance.isZero
            else { return nil }

            let name = (token["name"] as? String) ?? symbol
            return Holding(
                chain: chain,
                token: KnownToken(symbol: String(symbol.prefix(12)), name: name, address: contract, decimals: decimals),
                balance: balance,
                usdPrice: (token["exchange_rate"] as? String).flatMap { Double($0) }
            )
        }
    }

    /// NFT collections (ERC-721 and ERC-1155) the address holds tokens from.
    static func nftCollections(_ chain: Chain, address: String) async throws -> [NftCollection] {
        let items = try await list(chain, path: "addresses/\(address)/nft/collections?type=ERC-721%2CERC-1155")
        return items.compactMap { item in
            guard let token = item["token"] as? [String: Any],
                  token["reputation"] as? String != "scam",
                  let contract = token["address_hash"] as? String
            else { return nil }

            let instances = item["token_instances"] as? [[String: Any]] ?? []
            let tokenIds = instances.compactMap { $0["id"] as? String }
            let standard = (token["type"] as? String) ?? "NFT"

            // For ERC-721 the amount is how many NFTs are held. For ERC-1155 it
            // is a quantity that can run to 10^18 and more, so those count
            // distinct token ids instead — as does any amount too large to be
            // a believable number of NFTs.
            var count = max(tokenIds.count, 1)
            if standard == "ERC-721", let amount = (item["amount"] as? String).flatMap({ Int($0) }),
               (1...100_000).contains(amount) {
                count = amount
            }

            let name = (token["name"] as? String) ?? (token["symbol"] as? String) ?? "Unnamed collection"
            return NftCollection(
                chain: chain, address: contract, name: name,
                standard: standard, count: count, tokenIds: tokenIds
            )
        }
    }

    /// The latest movements for an address, newest first: coin transfers,
    /// token and NFT transfers, and contract calls it made.
    static func activity(_ chain: Chain, address: String) async throws -> [ActivityItem] {
        async let pendingTransactions = list(chain, path: "addresses/\(address)/transactions")
        async let pendingTransfers = list(chain, path: "addresses/\(address)/token-transfers")
        let (transactions, transfers) = try await (pendingTransactions, pendingTransfers)

        let me = address.lowercased()
        var entries: [ActivityItem] = []

        for (index, transfer) in transfers.enumerated() {
            guard let hash = transfer["transaction_hash"] as? String else { continue }
            let from = addressHash(transfer["from"])
            let to = addressHash(transfer["to"])
            let direction = movement(from: from, to: to, me: me)
            let kind = transfer["type"] as? String

            let title: String
            switch (direction, kind) {
            case (.incoming, "token_minting"): title = "Minted"
            case (.outgoing, "token_burning"): title = "Burned"
            case (.incoming, _): title = "Received"
            case (.outgoing, _): title = "Sent"
            case (.neutral, _): title = "Moved"
            }

            entries.append(ActivityItem(
                id: "\(hash)-t\(index)",
                hash: hash,
                date: date(transfer["timestamp"]),
                direction: direction,
                title: title,
                amountText: transferAmount(transfer),
                counterparty: direction == .incoming ? from : to,
                failed: false,
                url: chain.transactionURL(hash)
            ))
        }

        // A token transfer the wallet sent also shows up as a transaction
        // (a call to the token contract); it is listed once, as the transfer.
        let transferHashes = Set(transfers.compactMap { $0["transaction_hash"] as? String })

        for (index, transaction) in transactions.enumerated() {
            guard let hash = transaction["hash"] as? String else { continue }
            let value = (transaction["value"] as? String).flatMap { BigUInt(decimalString: $0) } ?? .zero
            guard !value.isZero || !transferHashes.contains(hash) else { continue }

            let from = addressHash(transaction["from"])
            let to = addressHash(transaction["to"])
            let direction = movement(from: from, to: to, me: me)

            let title: String
            let amountText: String?
            if value.isZero {
                title = (transaction["method"] as? String).map(methodTitle) ?? "Contract call"
                amountText = nil
            } else {
                title = direction == .incoming ? "Received" : "Sent"
                amountText = "\(TokenAmount.format(value, decimals: 18)) \(chain.symbol)"
            }

            entries.append(ActivityItem(
                id: "\(hash)-x\(index)",
                hash: hash,
                date: date(transaction["timestamp"]),
                direction: value.isZero ? .neutral : direction,
                title: title,
                amountText: amountText,
                counterparty: direction == .incoming ? from : to,
                failed: transaction["status"] as? String == "error",
                url: chain.transactionURL(hash)
            ))
        }

        // No timestamp means not mined yet, so pending entries lead the list.
        let newestFirst = entries.sorted { ($0.date ?? .distantFuture) > ($1.date ?? .distantFuture) }
        return Array(newestFirst.prefix(maxEntries))
    }

    // MARK: - Parsing

    private static func addressHash(_ value: Any?) -> String? {
        ((value as? [String: Any])?["hash"] as? String)?.lowercased()
    }

    private static func movement(from: String?, to: String?, me: String) -> ActivityItem.Direction {
        if to == me, from != me { return .incoming }
        if from == me, to != me { return .outgoing }
        return .neutral
    }

    /// "25 USDC" for a fungible token, "#1888 MoAI" for an NFT.
    private static func transferAmount(_ transfer: [String: Any]) -> String? {
        let token = transfer["token"] as? [String: Any] ?? [:]
        let total = transfer["total"] as? [String: Any] ?? [:]
        let label = (token["symbol"] as? String) ?? (token["name"] as? String) ?? "token"

        if let tokenId = total["token_id"] as? String {
            let shortId = tokenId.count > 10 ? "\(tokenId.prefix(4))…\(tokenId.suffix(4))" : tokenId
            return "#\(shortId) \(label.prefix(14))"
        }
        guard let value = (total["value"] as? String).flatMap({ BigUInt(decimalString: $0) }) else { return nil }
        let decimals = (total["decimals"] as? String).flatMap { Int($0) } ?? 0
        return "\(TokenAmount.format(value, decimals: decimals)) \(label.prefix(12))"
    }

    /// `safeTransferFrom` → "Safe transfer from"; a bare selector stays "Contract call".
    private static func methodTitle(_ method: String) -> String {
        guard !method.hasPrefix("0x"), !method.isEmpty else { return "Contract call" }
        var words = ""
        for character in method {
            if character.isUppercase, !words.isEmpty { words.append(" ") }
            words.append(contentsOf: character.lowercased())
        }
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// Timestamps arrive as `2026-10-08T18:50:47.000000Z`.
    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let seconds = text.split(separator: ".").first.map(String.init) ?? text
        return try? Date(seconds.hasSuffix("Z") ? seconds : seconds + "Z", strategy: .iso8601)
    }

    // MARK: - Transport

    /// GETs a list endpoint and returns its `items`.
    private static func list(_ chain: Chain, path: String) async throws -> [[String: Any]] {
        guard let base = chain.indexerURL, let url = URL(string: "\(base)/api/v2/\(path)") else {
            throw RpcError(message: "\(chain.name) has no indexer.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        // An address the indexer has never seen answers 404: it holds nothing.
        if (response as? HTTPURLResponse)?.statusCode == 404 { return [] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            throw RpcError(message: "The \(chain.name) indexer didn't answer.")
        }
        return items
    }
}
