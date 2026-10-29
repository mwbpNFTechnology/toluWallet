//
//  ColdSetupPayloadTests.swift
//  toluWalletTests
//
//  The setup the app hands a toluCold device, against the bytes the
//  firmware's tests parse (tolu_cold/test/test_card.cpp).
//

import Foundation
import Testing
@testable import toluWallet

@MainActor
struct ColdSetupPayloadTests {

    private let key: [UInt8] = [0x12, 0x22, 0x22, 0x21]
    private let phoneKeySlot: [UInt8] = [0x12, 0x22, 0x22, 0x22]
    private let phoneKey = Hex.bytes(PhoneKeyObjectTests.phoneKey) ?? []

    @Test func matchesTheFirmwareExample() throws {
        let payload = try #require(ColdSetupPayload.make(
            keyObjectID: key, phoneKeyObjectID: phoneKeySlot, phoneKey: phoneKey
        ))
        #expect(Hex.string(payload) == "02" + "12222221" + "12222222" + PhoneKeyObjectTests.phoneKey)
    }

    /// The instruction bytes the firmware answers (tolu_cold/cold_target.h).
    @Test func commandsMatchTheFirmware() {
        #expect(ColdDeviceCommand.instructionClass == 0x80)
        #expect(ColdDeviceCommand.setup(Data([1, 2])).instruction == 0x20)
        #expect(ColdDeviceCommand.setup(Data([1, 2])).data == Data([1, 2]))
        #expect(ColdDeviceCommand.cancel.instruction == 0x21)
        #expect(ColdDeviceCommand.cancel.data.isEmpty)
    }

    @Test func refusesWhatTheDeviceWouldRefuse() {
        #expect(ColdSetupPayload.make(keyObjectID: key, phoneKeyObjectID: key, phoneKey: phoneKey) == nil)
        #expect(ColdSetupPayload.make(keyObjectID: [0, 0, 0, 0], phoneKeyObjectID: phoneKeySlot, phoneKey: phoneKey) == nil)
        #expect(ColdSetupPayload.make(keyObjectID: [0x7F, 0xFF, 0x02, 0x06], phoneKeyObjectID: phoneKeySlot,
                                      phoneKey: phoneKey) == nil)
        #expect(ColdSetupPayload.make(keyObjectID: key, phoneKeyObjectID: phoneKeySlot,
                                      phoneKey: Array(phoneKey.dropLast())) == nil)
        #expect(ColdSetupPayload.make(keyObjectID: key, phoneKeyObjectID: phoneKeySlot,
                                      phoneKey: [0x02] + phoneKey.dropFirst()) == nil)
        #expect(ColdSetupPayload.make(keyObjectID: [0x12], phoneKeyObjectID: phoneKeySlot, phoneKey: phoneKey) == nil)
    }

    @Test func readsAddressesFromQRCodes() {
        let address = "0x9858EfFD232B4033E47d90003D41EC34EcaEda94"
        #expect(EthereumAddress.fromScanned(address) == address.lowercased())
        #expect(EthereumAddress.fromScanned("ethereum:\(address)@1") == address.lowercased())
        #expect(EthereumAddress.fromScanned("  \(address)\n") == address.lowercased())
        // One character in the wrong case fails the checksum the device printed.
        #expect(EthereumAddress.fromScanned("0x9858EfFD232B4033E47d90003D41EC34EcaEda9A") == nil)
        #expect(EthereumAddress.fromScanned("tolu://sign?to=0x00") == nil)
    }
}
