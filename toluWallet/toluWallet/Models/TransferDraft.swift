//
//  TransferDraft.swift
//  toluWallet
//
//  What the person asked to send, before fees are known.
//

import Foundation

struct TransferDraft: Equatable {
    let holding: Holding
    /// Lower-case `0x` recipient address.
    let recipient: String
    /// Amount in base units.
    let amount: BigUInt
    /// True when the whole balance was asked for. For a native coin the
    /// network fee is then taken out of the amount.
    let sendsMaximum: Bool
}
