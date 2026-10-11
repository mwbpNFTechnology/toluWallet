//
//  TransferController.swift
//  toluWallet
//
//  Runs one transfer end to end: build the transaction, have the tag sign it,
//  broadcast it, and wait for the block that carries it. After tolu's vault
//  send controller — but here the tag's own address pays, so the tag's
//  signature is the whole authorisation.
//

import Foundation

@Observable
final class TransferController {

    enum Step: Int, CaseIterable, Identifiable {
        case prepare, sign, send, confirm

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .prepare: return "Transfer prepared"
            case .sign: return "Tag signs"
            case .send: return "Sent to the network"
            case .confirm: return "Settled on-chain"
            }
        }
    }

    let wallet: WalletRecord
    let draft: TransferDraft

    private(set) var current: Step = .prepare
    private(set) var running = false
    private(set) var isComplete = false
    private(set) var error: String?
    /// The step the last error happened in.
    private(set) var failedStep: Step?
    /// What will actually leave the wallet (a max send has the fee taken out).
    private(set) var amount: BigUInt
    /// Upper bound on the network fee, once the transaction is built.
    private(set) var networkFee: BigUInt?
    private(set) var nonceText: String?
    private(set) var txHash: String?

    @ObservationIgnored private var transaction: EvmTransaction?
    @ObservationIgnored private var signedTransaction: [UInt8]?
    @ObservationIgnored private let runner = Se05xNfcRunner()
    @ObservationIgnored private var task: Task<Void, Never>?

    init(wallet: WalletRecord, draft: TransferDraft) {
        self.wallet = wallet
        self.draft = draft
        amount = draft.amount
    }

    var chain: Chain { draft.holding.chain }

    /// Once the transaction is out it can't be edited or taken back.
    var hasBroadcast: Bool { txHash != nil }

    var amountText: String {
        TokenAmount.exact(amount, decimals: draft.holding.decimals)
    }

    var networkFeeText: String? {
        networkFee.map { "≤ \(TokenAmount.format($0, decimals: 18, places: 6)) \(chain.symbol)" }
    }

    var explorerURL: URL? {
        txHash.flatMap { chain.transactionURL($0) }
    }

    // MARK: - Presentation

    func state(for step: Step) -> StepState {
        if isComplete { return .done }
        if failedStep == step { return .error }
        if step.rawValue < current.rawValue { return .done }
        if step == current, error == nil { return .active }
        return .pending
    }

    func hint(for step: Step) -> String {
        switch step {
        case .prepare:
            if let nonceText, let networkFeeText { return "nonce \(nonceText) · fee \(networkFeeText)" }
            return "reading the nonce, gas and fees"
        case .sign:
            return "password session, then the tag signs"
        case .send:
            return txHash.map { "tx " + EthereumAddress.short($0) } ?? "broadcast to \(chain.name)"
        case .confirm:
            return isComplete ? "included in a block" : "waiting for the block that carries it"
        }
    }

    var statusText: String {
        if isComplete { return "sent" }
        if error != nil { return "needs attention" }
        switch current {
        case .prepare: return "preparing"
        case .sign: return running ? "hold the tag" : "awaiting the tag"
        case .send: return "sending"
        case .confirm: return "waiting for the chain"
        }
    }

    var actionTitle: String {
        if isComplete { return "Done" }
        if error != nil { return failedStep == .confirm ? "Keep waiting" : "Try again" }
        switch current {
        case .prepare: return "Preparing…"
        case .sign: return running ? "Hold the tag…" : "Tap tag to sign"
        case .send: return "Sending…"
        case .confirm: return "Waiting for confirmation"
        }
    }

    var actionEnabled: Bool { isComplete || !running }

    // MARK: - Running

    /// Advances as far as it can: straight through to the end, except that it
    /// stops before signing so the person chooses when to tap the tag.
    func run() {
        guard !running, !isComplete else { return }
        task = Task { await advance() }
    }

    /// Starts the read-only first step. Never starts a tag tap by itself.
    func prepareIfNeeded() {
        guard current == .prepare, error == nil else { return }
        run()
    }

    func cancel() {
        task?.cancel()
    }

    private func advance() async {
        running = true
        error = nil
        failedStep = nil
        defer { running = false }

        do {
            while !isComplete {
                try Task.checkCancellation()
                switch current {
                case .prepare:
                    try await prepare()
                    current = .sign
                    return
                case .sign:
                    try await sign()
                    current = .send
                case .send:
                    try await broadcast()
                    current = .confirm
                case .confirm:
                    try await confirm()
                    isComplete = true
                }
            }
        } catch is CancellationError {
            // The screen was closed.
        } catch {
            failedStep = current
            self.error = NfcErrorText.describe(error)
            // A node that rejects the transaction will reject it again, so
            // start over with a fresh nonce and fee rather than re-sending.
            if current == .send, error is RpcError {
                current = .prepare
                transaction = nil
                signedTransaction = nil
            }
        }
    }

    // MARK: - Steps

    private func prepare() async throws {
        let holding = draft.holding
        guard let recipient = EthereumAddress.bytes(draft.recipient) else {
            throw TransferError.invalidRecipient
        }

        async let pendingNonce = EvmRpc.transactionCount(chain, address: wallet.address)
        async let pendingBalance = EvmRpc.nativeBalance(chain, address: wallet.address)
        let fee = try await EvmRpc.suggestedFee(chain)
        let (nonce, nativeBalance) = try await (pendingNonce, pendingBalance)

        // A native coin goes straight to the recipient; a token is a call to
        // its contract, which carries the recipient and amount as data.
        let target: [UInt8]
        let data: [UInt8]
        var value: BigUInt
        if let token = holding.token {
            guard let contract = EthereumAddress.bytes(token.address) else {
                throw TransferError.invalidRecipient
            }
            target = contract
            data = Erc20.transfer(to: recipient, amount: draft.amount)
            value = .zero
        } else {
            target = recipient
            data = []
            value = draft.amount
        }

        // A max send is estimated with no value: the full balance leaves the
        // node nothing to cover gas with in its own check.
        let estimate = try await EvmRpc.estimateGas(
            chain, from: wallet.address, to: "0x" + Hex.string(target),
            value: holding.isNative && draft.sendsMaximum ? .zero : value, data: data
        )
        // 21000 is exact for a plain transfer; anything else gets headroom.
        let gasLimit = estimate == BigUInt(21_000) ? estimate : estimate.scaled(by: 12, over: 10)

        func build(value: BigUInt) -> EvmTransaction {
            EvmTransaction(chainId: chain.id, nonce: nonce, fee: fee, gasLimit: gasLimit,
                           to: target, value: value, data: data)
        }

        var transaction = build(value: value)
        var feeBound = transaction.maxNetworkFee
        if chain.hasL1DataFee,
           let l1Fee = try? await EvmRpc.l1DataFee(chain, transaction: transaction.signingPayload) {
            // The L1 fee moves before inclusion, so reserve half as much again.
            feeBound = feeBound + l1Fee.scaled(by: 3, over: 2)
        }

        let feeText = TokenAmount.format(feeBound, decimals: 18, places: 6)
        if holding.isNative {
            if draft.sendsMaximum {
                guard nativeBalance > feeBound else {
                    throw TransferError.needsGas(fee: feeText, symbol: chain.symbol, chain: chain.name)
                }
                value = nativeBalance - feeBound
                transaction = build(value: value)
            } else {
                let needed = value + feeBound
                guard nativeBalance >= needed else {
                    throw TransferError.insufficientFunds(
                        needed: TokenAmount.format(needed, decimals: 18, places: 6), symbol: chain.symbol
                    )
                }
            }
            amount = value
        } else {
            guard nativeBalance >= feeBound else {
                throw TransferError.needsGas(fee: feeText, symbol: chain.symbol, chain: chain.name)
            }
        }

        networkFee = feeBound
        nonceText = nonce.decimalString
        self.transaction = transaction
        signedTransaction = nil
    }

    private func sign() async throws {
        guard let transaction,
              let key = ObjectId.parse(wallet.keyObjectID),
              let slot = ObjectId.parse(wallet.passwordObjectID) else {
            throw TransferError.notPrepared
        }
        let hash = transaction.signingHash
        let expectedAddress = wallet.address.lowercased()
        let passwordBytes = Array(wallet.password.utf8)

        let (der, point) = try await runner.run(
            alertMessage: "Hold your iPhone near the tolu tag to sign"
        ) { tag in
            try await tag.openUserIdSession(userObjectId: slot.bytes, pin: passwordBytes)
            let point = try await tag.readPublicKeyPoint(objectId: key.bytes)
            // Same slot and password on another tag would sign for another address.
            guard EthereumAddress.from(publicKeyPoint: point) == expectedAddress else {
                throw TransferError.wrongTag
            }
            let der = try await tag.signDigest(objectId: key.bytes, digest: hash)
            return (der, point)
        }

        guard let signature = await TransactionSigner.recoverSignature(der: der, hash: hash, publicKey: point) else {
            throw TransferError.badSignature
        }
        signedTransaction = transaction.serialized(with: signature)
    }

    private func broadcast() async throws {
        guard let signedTransaction else { throw TransferError.notPrepared }
        do {
            txHash = try await EvmRpc.sendRawTransaction(chain, signed: signedTransaction)
        } catch let error as RpcError where Self.meansAlreadySent(error.message) {
            // A retry after a dropped connection: the first attempt did land.
            txHash = "0x" + Hex.string(Keccak256.digest(signedTransaction))
        }
    }

    private static func meansAlreadySent(_ message: String) -> Bool {
        ["already known", "known transaction", "already exists"].contains {
            message.localizedCaseInsensitiveContains($0)
        }
    }

    private func confirm() async throws {
        guard let txHash else { throw TransferError.notPrepared }
        // About three minutes; a transient RPC failure just means ask again.
        for _ in 0..<60 {
            if let succeeded = try? await EvmRpc.receiptStatus(chain, hash: txHash) {
                if succeeded { return }
                throw TransferError.reverted
            }
            try await Task.sleep(for: .seconds(3))
        }
        throw TransferError.stillPending
    }
}
