//
//  EvmRpc.swift
//  toluWallet
//
//  The JSON-RPC calls a wallet makes: balances, the pieces of a transaction
//  (nonce, fees, gas), broadcast, and the receipt.
//

import Foundation

enum EvmRpc {

    // MARK: - Balances

    static func nativeBalance(_ chain: Chain, address: String) async throws -> BigUInt {
        try await quantity(chain, method: "eth_getBalance", params: [address, "latest"])
    }

    /// `balanceOf(holder)` on an ERC-20 contract.
    static func tokenBalance(_ chain: Chain, token: String, holder: String) async throws -> BigUInt {
        guard let holderBytes = EthereumAddress.bytes(holder) else {
            throw RpcError(message: "The wallet address isn't valid.")
        }
        let data = Erc20.balanceOf(holderBytes)
        let result = try await string(chain, method: "eth_call",
                                      params: [["to": token, "data": "0x" + Hex.string(data)], "latest"])
        // "0x" means there is no contract at that address on this chain.
        guard result.count > 2, let value = BigUInt(hex: result) else {
            throw RpcError(message: "The token contract didn't answer.")
        }
        return value
    }

    // MARK: - Building a transaction

    /// The next nonce, counting transactions still in the mempool.
    static func transactionCount(_ chain: Chain, address: String) async throws -> BigUInt {
        try await quantity(chain, method: "eth_getTransactionCount", params: [address, "pending"])
    }

    /// EIP-1559 fees when the chain has a base fee, otherwise a legacy gas price.
    /// The fee cap is twice the current base fee plus the tip, so the
    /// transaction survives the base fee rising over the next few blocks.
    static func suggestedFee(_ chain: Chain) async throws -> EvmTransaction.Fee {
        let block = try await request(chain, method: "eth_getBlockByNumber", params: ["latest", false])
        guard let baseFeeHex = (block as? [String: Any])?["baseFeePerGas"] as? String,
              let baseFee = BigUInt(hex: baseFeeHex) else {
            return .legacy(gasPrice: try await quantity(chain, method: "eth_gasPrice", params: []))
        }

        let tip: BigUInt
        if let suggested = try? await quantity(chain, method: "eth_maxPriorityFeePerGas", params: []) {
            tip = suggested
        } else {
            let gasPrice = try await quantity(chain, method: "eth_gasPrice", params: [])
            tip = gasPrice > baseFee ? gasPrice - baseFee : .zero
        }
        return .eip1559(maxPriorityFeePerGas: tip, maxFeePerGas: baseFee * BigUInt(2) + tip)
    }

    static func estimateGas(_ chain: Chain, from: String, to: String,
                            value: BigUInt, data: [UInt8]) async throws -> BigUInt {
        var call: [String: Any] = ["from": from, "to": to, "value": value.hexQuantity]
        if !data.isEmpty { call["data"] = "0x" + Hex.string(data) }
        return try await quantity(chain, method: "eth_estimateGas", params: [call])
    }

    /// The L1 data fee an OP-stack chain charges for these transaction bytes,
    /// read from the chain's GasPriceOracle predeploy.
    static func l1DataFee(_ chain: Chain, transaction: [UInt8]) async throws -> BigUInt {
        let oracle = "0x420000000000000000000000000000000000000F"
        let data = OpStackOracle.getL1Fee(transaction)
        return try await quantity(chain, method: "eth_call",
                                  params: [["to": oracle, "data": "0x" + Hex.string(data)], "latest"])
    }

    // MARK: - Sending

    /// Broadcasts a signed transaction and returns its hash.
    static func sendRawTransaction(_ chain: Chain, signed: [UInt8]) async throws -> String {
        try await string(chain, method: "eth_sendRawTransaction", params: ["0x" + Hex.string(signed)])
    }

    /// `nil` while the transaction is still pending; otherwise whether it succeeded.
    static func receiptStatus(_ chain: Chain, hash: String) async throws -> Bool? {
        let result = try await request(chain, method: "eth_getTransactionReceipt", params: [hash])
        guard let receipt = result as? [String: Any], let status = receipt["status"] as? String else {
            return nil
        }
        return BigUInt(hex: status) == .one
    }

    // MARK: - Transport

    private static func quantity(_ chain: Chain, method: String, params: [Any]) async throws -> BigUInt {
        let text = try await string(chain, method: method, params: params)
        guard let value = BigUInt(hex: text) else {
            throw RpcError(message: "\(chain.name) returned an unexpected value.")
        }
        return value
    }

    private static func string(_ chain: Chain, method: String, params: [Any]) async throws -> String {
        guard let text = try await request(chain, method: method, params: params) as? String else {
            throw RpcError(message: "\(chain.name) returned an unexpected response.")
        }
        return text
    }

    /// Sends one JSON-RPC request and returns its `result` (which may be `NSNull`).
    private static func request(_ chain: Chain, method: String, params: [Any]) async throws -> Any {
        guard let url = URL(string: chain.rpcURL) else {
            throw RpcError(message: "The \(chain.name) RPC URL isn't valid.")
        }
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": method, "params": params]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RpcError(message: "\(chain.name) didn't answer with JSON-RPC.")
        }
        if let error = json["error"] as? [String: Any] {
            throw RpcError(message: error["message"] as? String ?? "\(chain.name) RPC error")
        }
        guard let result = json["result"] else {
            throw RpcError(message: "\(chain.name) returned an unexpected response.")
        }
        return result
    }
}
