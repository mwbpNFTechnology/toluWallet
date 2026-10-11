//
//  TransferFormModel.swift
//  toluWallet
//
//  What is typed on the first transfer screen, and whether it adds up to
//  something that can be sent. Owned by the flow, so going back from the
//  signing screen finds the form as it was left.
//

import Foundation

@Observable
final class TransferFormModel {

    let wallet: WalletRecord
    /// What the wallet holds, by chain id.
    let holdings: [Holding]

    var selectedID: Holding.ID?
    var amountText = ""
    var recipientText = ""

    init(wallet: WalletRecord, holdings: [Holding]) {
        self.wallet = wallet
        self.holdings = holdings
        selectedID = holdings.first?.id
    }

    var selected: Holding? {
        holdings.first { $0.id == selectedID } ?? holdings.first
    }

    /// The typed amount in base units.
    var amount: BigUInt? {
        guard let selected else { return nil }
        return TokenAmount.parse(amountText, decimals: selected.decimals)
    }

    var sendsMaximum: Bool {
        guard let selected, let amount else { return false }
        return amount == selected.balance
    }

    private var recipient: String {
        recipientText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var recipientLooksWrong: Bool {
        !recipient.isEmpty && !EthereumAddress.isValid(recipient)
    }

    /// What is in the way of reviewing, in the order worth fixing.
    var blocker: String? {
        guard let selected else { return "Nothing to send yet. Receive something first." }
        guard let amount else { return "Enter an amount — up to \(selected.decimals) decimals." }
        if amount.isZero { return "Amount has to be more than zero." }
        if amount > selected.balance {
            return "This wallet holds \(selected.balanceText) \(selected.symbol) on \(selected.chain.name)."
        }
        if recipient.isEmpty { return "Enter the address this goes to." }
        guard EthereumAddress.bytes(recipient) != nil else { return "That isn't a full address." }
        guard EthereumAddress.isValid(recipient) else {
            return "That address has a typo — its checksum doesn't match."
        }
        if recipient.lowercased() == wallet.address.lowercased() { return "That is this wallet's own address." }
        return nil
    }

    var draft: TransferDraft? {
        guard blocker == nil, let selected, let amount else { return nil }
        return TransferDraft(holding: selected, recipient: recipient.lowercased(),
                             amount: amount, sendsMaximum: sendsMaximum)
    }

    func select(_ holding: Holding) {
        guard holding.id != selectedID else { return }
        selectedID = holding.id
        amountText = ""
    }

    func fillMaximum() {
        guard let selected else { return }
        amountText = TokenAmount.exact(selected.balance, decimals: selected.decimals)
    }

    func pasteRecipient() {
        guard let text = Clipboard.text else { return }
        recipientText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
