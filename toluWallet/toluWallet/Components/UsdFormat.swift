//
//  UsdFormat.swift
//  toluWallet
//
//  Dollar amounts as they are shown next to balances.
//

import Foundation

enum UsdFormat {

    static func string(_ value: Double) -> String {
        if value > 0, value < 0.01 { return "<$0.01" }
        return value.formatted(.currency(code: "USD").presentation(.narrow).locale(Locale(identifier: "en_US")))
    }
}
