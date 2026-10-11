//
//  TransactionEncodingTests.swift
//  toluWalletTests
//
//  Checks transaction serialization, hashing and signature recovery against
//  values produced by ethers v6 for a known test key. The first case is the
//  worked example from EIP-155.
//

import Foundation
import Testing
@testable import toluWallet

@MainActor
struct TransactionEncodingTests {

    /// Public key of the EIP-155 example private key (0x46 repeated).
    private let publicKey = Hex.bytes(
        "044bc2a31265153f07e70e0bab08724e6b85e217f8cd628ceb62974247bb493382ce28cab79ad7119ee1ad3ebcdb98a16805211530ecc6cfefa1b88e6dff99232a"
    )!

    private var legacy: EvmTransaction {
        EvmTransaction(
            chainId: 1, nonce: BigUInt(9), fee: .legacy(gasPrice: BigUInt(20_000_000_000)),
            gasLimit: BigUInt(21_000),
            to: EthereumAddress.bytes("0x3535353535353535353535353535353535353535")!,
            value: BigUInt(1_000_000_000_000_000_000), data: []
        )
    }

    private var dynamicFee: EvmTransaction {
        EvmTransaction(
            chainId: 8453, nonce: .zero,
            fee: .eip1559(maxPriorityFeePerGas: BigUInt(1_000_000), maxFeePerGas: BigUInt(11_000_000)),
            gasLimit: BigUInt(21_000),
            to: EthereumAddress.bytes("0x2b5ad5c4795c026514f8317c7a215e218dccd6cf")!,
            value: BigUInt(123_456_789_012_345_678), data: []
        )
    }

    @Test func legacyTransactionMatchesEip155Example() throws {
        #expect(Hex.string(legacy.signingPayload)
                == "ec098504a817c800825208943535353535353535353535353535353535353535880de0b6b3a764000080018080")
        #expect(Hex.string(legacy.signingHash)
                == "daf5a779ae972f972197303d7b574746c7ef83eadac0f2791ad23db92e4c8e53")

        let der = Hex.bytes("3044022028ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276022067cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83")!
        let signature = try #require(TransactionSigner.signature(der: der, hash: legacy.signingHash, publicKey: publicKey))
        #expect(signature.yParity == 0)
        #expect(Hex.string(legacy.serialized(with: signature))
                == "f86c098504a817c800825208943535353535353535353535353535353535353535880de0b6b3a76400008025a028ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276a067cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83")
    }

    @Test func dynamicFeeTransactionMatchesEthers() throws {
        #expect(Hex.string(dynamicFee.signingPayload)
                == "02ef82210580830f424083a7d8c0825208942b5ad5c4795c026514f8317c7a215e218dccd6cf8801b69b4ba630f34e80c0")
        #expect(Hex.string(dynamicFee.signingHash)
                == "58467b90e18927d5a4f8ea23ee1db7ca7e95737017e746f6045877c596afff08")

        let der = Hex.bytes("3044022051017c1d63a8aef3632ee4239f80a47fccec72150989857d90bd2d037044c718022071886ba26e977bbbb48fa14beeab423f48ace4bccded8ca7cca624f915a9fafa")!
        let signature = try #require(TransactionSigner.signature(der: der, hash: dynamicFee.signingHash, publicKey: publicKey))
        #expect(signature.yParity == 1)

        let signed = dynamicFee.serialized(with: signature)
        #expect(Hex.string(signed)
                == "02f87282210580830f424083a7d8c0825208942b5ad5c4795c026514f8317c7a215e218dccd6cf8801b69b4ba630f34e80c001a051017c1d63a8aef3632ee4239f80a47fccec72150989857d90bd2d037044c718a071886ba26e977bbbb48fa14beeab423f48ace4bccded8ca7cca624f915a9fafa")
        #expect(Hex.string(Keccak256.digest(signed))
                == "c7a65e1b055950b02b62aec699cbc0e24bff4bff43d683a69f6354b6331d1eb7")
    }

    /// The tag may return either S; the transaction must always carry the low one.
    @Test func highSSignatureIsNormalized() throws {
        let highS = Hex.bytes("3045022051017c1d63a8aef3632ee4239f80a47fccec72150989857d90bd2d037044c7180221008e77945d916884444b705eb41154bdbf7201f829e15b1393f32c3993ba8c4647")!
        let signature = try #require(TransactionSigner.signature(der: highS, hash: dynamicFee.signingHash, publicKey: publicKey))
        #expect(signature.yParity == 1)
        #expect(signature.s <= Secp256k1.halfN)
    }

    /// A signature that doesn't recover to the tag's key must never be used.
    @Test func signatureFromAnotherKeyIsRejected() {
        var otherKey = publicKey
        otherKey[40] ^= 0x01
        let der = Hex.bytes("3044022051017c1d63a8aef3632ee4239f80a47fccec72150989857d90bd2d037044c718022071886ba26e977bbbb48fa14beeab423f48ace4bccded8ca7cca624f915a9fafa")!
        #expect(TransactionSigner.signature(der: der, hash: dynamicFee.signingHash, publicKey: otherKey) == nil)
    }

    @Test func erc20TransferCallData() {
        let recipient = EthereumAddress.bytes("0x2b5ad5c4795c026514f8317c7a215e218dccd6cf")!
        #expect(Hex.string(Erc20.transfer(to: recipient, amount: BigUInt(2_500_000)))
                == "a9059cbb0000000000000000000000002b5ad5c4795c026514f8317c7a215e218dccd6cf00000000000000000000000000000000000000000000000000000000002625a0")
    }
}
