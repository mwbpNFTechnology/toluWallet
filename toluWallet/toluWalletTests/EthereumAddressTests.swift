//
//  EthereumAddressTests.swift
//  toluWalletTests
//

import Testing
@testable import toluWallet

@MainActor
struct EthereumAddressTests {

    @Test func derivesAddressFromPublicKey() throws {
        let point = try #require(Hex.bytes(
            "044bc2a31265153f07e70e0bab08724e6b85e217f8cd628ceb62974247bb493382ce28cab79ad7119ee1ad3ebcdb98a16805211530ecc6cfefa1b88e6dff99232a"
        ))
        #expect(EthereumAddress.from(publicKeyPoint: point) == "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f")
    }

    @Test func appliesEip55Checksum() {
        #expect(EthereumAddress.checksummed("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed")
                == "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
    }

    @Test func validatesRecipients() {
        #expect(EthereumAddress.isValid("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed"))
        #expect(EthereumAddress.isValid("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"))
        // One letter in the wrong case breaks the checksum.
        #expect(!EthereumAddress.isValid("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAeD"))
        #expect(!EthereumAddress.isValid("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beae"))
        #expect(!EthereumAddress.isValid("not an address"))
    }
}
