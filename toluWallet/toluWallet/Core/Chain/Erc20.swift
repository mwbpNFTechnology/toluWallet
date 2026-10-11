//
//  Erc20.swift
//  toluWallet
//
//  Call data for the two ERC-20 functions the wallet uses.
//

import Foundation

enum Erc20 {

    /// `balanceOf(address)` — selector 0x70a08231.
    static func balanceOf(_ holder: [UInt8]) -> [UInt8] {
        [0x70, 0xA0, 0x82, 0x31] + AbiWord.address(holder)
    }

    /// `transfer(address,uint256)` — selector 0xa9059cbb.
    static func transfer(to recipient: [UInt8], amount: BigUInt) -> [UInt8] {
        [0xA9, 0x05, 0x9C, 0xBB] + AbiWord.address(recipient) + AbiWord.uint(amount)
    }
}
