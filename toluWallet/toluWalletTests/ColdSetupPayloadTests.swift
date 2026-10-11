//
//  ColdSetupPayloadTests.swift
//  toluWalletTests
//
//  The same bytes are fed to the firmware's parser in its own test, so the
//  phone and the device are checked against one example.
//

import Foundation
import Testing
@testable import toluWallet

@MainActor
struct ColdSetupPayloadTests {

    private let key: [UInt8] = [0x12, 0x22, 0x22, 0x21]
    private let passwordSlot: [UInt8] = [0x12, 0x22, 0x22, 0x22]

    @Test func matchesTheFirmwareExample() throws {
        let payload = try #require(ColdSetupPayload.make(
            keyObjectID: key, passwordObjectID: passwordSlot, password: Array("abcdef".utf8)
        ))
        #expect(Hex.string(payload) == "011222222112222222" + "06" + "616263646566")
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
        let password = Array("abcdef".utf8)
        #expect(ColdSetupPayload.make(keyObjectID: key, passwordObjectID: key, password: password) == nil)
        #expect(ColdSetupPayload.make(keyObjectID: [0, 0, 0, 0], passwordObjectID: passwordSlot, password: password) == nil)
        #expect(ColdSetupPayload.make(keyObjectID: [0x7F, 0xFF, 0x02, 0x06], passwordObjectID: passwordSlot, password: password) == nil)
        #expect(ColdSetupPayload.make(keyObjectID: key, passwordObjectID: passwordSlot, password: Array("abc".utf8)) == nil)
        #expect(ColdSetupPayload.make(keyObjectID: key, passwordObjectID: passwordSlot, password: Array(repeating: 0x61, count: 17)) == nil)
        #expect(ColdSetupPayload.make(keyObjectID: [0x12], passwordObjectID: passwordSlot, password: password) == nil)
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
