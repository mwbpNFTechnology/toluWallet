//
//  ColdDeviceCommand.swift
//  toluWallet
//
//  The two things the phone can ask of a toluCold device. The firmware
//  answers the same instruction bytes (tolu_cold/cold_target.h) — change one
//  side and change the other.
//

import Foundation

enum ColdDeviceCommand {
    /// The slots and password of a new wallet (see `ColdSetupPayload`). Starts
    /// the ceremony — over again, if one was already running.
    case setup(Data)
    /// Stop whatever is going on and erase it. A device with nothing to
    /// cancel accepts it all the same.
    case cancel

    static let instructionClass: UInt8 = 0x80

    var instruction: UInt8 {
        switch self {
        case .setup: 0x20
        case .cancel: 0x21
        }
    }

    var data: Data {
        switch self {
        case .setup(let payload): payload
        case .cancel: Data()
        }
    }
}
