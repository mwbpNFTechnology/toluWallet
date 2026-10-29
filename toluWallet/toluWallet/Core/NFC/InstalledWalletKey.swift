//
//  InstalledWalletKey.swift
//  toluWallet
//
//  What one tap that put a wallet on a tag read back.
//

import Foundation

struct InstalledWalletKey {
    /// `04 ‖ X ‖ Y`, read inside the iPhone's session — so this key is
    /// bound to this iPhone.
    let publicKey: [UInt8]
    let cardUniqueId: String?
}
