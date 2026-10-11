//
//  RpcError.swift
//  toluWallet
//

import Foundation

struct RpcError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
