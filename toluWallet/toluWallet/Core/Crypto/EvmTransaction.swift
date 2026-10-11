//
//  EvmTransaction.swift
//  toluWallet
//
//  An unsigned EVM transaction: either EIP-1559 (type 2) or legacy with
//  EIP-155 replay protection, for chains that have no base fee. Produces the
//  hash the tag signs and the signed bytes that get broadcast.
//

import Foundation

struct EvmTransaction {

    enum Fee {
        case eip1559(maxPriorityFeePerGas: BigUInt, maxFeePerGas: BigUInt)
        case legacy(gasPrice: BigUInt)

        /// The most one unit of gas can cost.
        var cap: BigUInt {
            switch self {
            case .eip1559(_, let maxFeePerGas): return maxFeePerGas
            case .legacy(let gasPrice): return gasPrice
            }
        }
    }

    let chainId: Int
    let nonce: BigUInt
    let fee: Fee
    let gasLimit: BigUInt
    /// 20-byte recipient (the token contract, for an ERC-20 transfer).
    let to: [UInt8]
    let value: BigUInt
    let data: [UInt8]

    /// The most this transaction can spend on gas.
    var maxNetworkFee: BigUInt { gasLimit * fee.cap }

    /// The bytes whose Keccak-256 hash is signed.
    var signingPayload: [UInt8] {
        switch fee {
        case .eip1559:
            return [0x02] + Rlp.list(dynamicFeeFields)
        case .legacy:
            return Rlp.list(legacyFields + [Rlp.encode(chain), Rlp.encode([]), Rlp.encode([])])
        }
    }

    var signingHash: [UInt8] { Keccak256.digest(signingPayload) }

    /// The signed transaction, ready for `eth_sendRawTransaction`.
    func serialized(with signature: TransactionSignature) -> [UInt8] {
        let r = Rlp.encode(signature.r)
        let s = Rlp.encode(signature.s)
        switch fee {
        case .eip1559:
            let yParity = Rlp.encode(BigUInt(UInt64(signature.yParity)))
            return [0x02] + Rlp.list(dynamicFeeFields + [yParity, r, s])
        case .legacy:
            // EIP-155: v = chainId * 2 + 35 + yParity
            let v = chain * BigUInt(2) + BigUInt(UInt64(35 + signature.yParity))
            return Rlp.list(legacyFields + [Rlp.encode(v), r, s])
        }
    }

    // MARK: - Fields

    private var chain: BigUInt { BigUInt(UInt64(chainId)) }

    private var dynamicFeeFields: [[UInt8]] {
        guard case let .eip1559(maxPriorityFeePerGas, maxFeePerGas) = fee else { return [] }
        return [
            Rlp.encode(chain),
            Rlp.encode(nonce),
            Rlp.encode(maxPriorityFeePerGas),
            Rlp.encode(maxFeePerGas),
            Rlp.encode(gasLimit),
            Rlp.encode(to),
            Rlp.encode(value),
            Rlp.encode(data),
            Rlp.list([])    // access list
        ]
    }

    private var legacyFields: [[UInt8]] {
        guard case let .legacy(gasPrice) = fee else { return [] }
        return [
            Rlp.encode(nonce),
            Rlp.encode(gasPrice),
            Rlp.encode(gasLimit),
            Rlp.encode(to),
            Rlp.encode(value),
            Rlp.encode(data)
        ]
    }
}
