//
//  SeedPhraseTests.swift
//  toluWalletTests
//
//  A wallet made from a seed phrase on this phone: the word list, the phrase,
//  the key and the address against the values every standard wallet gives,
//  and the bytes this app has to share with the toluCold firmware.
//

import CryptoKit
import Foundation
import Testing
@testable import toluWallet

@MainActor
struct SeedPhraseTests {

    @Test func wordListIsThePublishedOne() {
        let text = Bip39Wordlist.words.joined(separator: "\n") + "\n"
        #expect(Bip39Wordlist.words.count == 2048)
        #expect(Hex.string(Array(SHA256.hash(data: Array(text.utf8))))
            == "2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda")
    }

    /// The all-zero phrase every BIP-39 implementation is checked with; the
    /// key and address are what the ethers library derives from it.
    @Test func derivesTheStandardTwelveWordWallet() throws {
        let words = try #require(Bip39.words(entropy: [UInt8](repeating: 0, count: 16)))
        #expect(words.joined(separator: " ")
            == "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
        #expect(Hex.string(Bip39.seed(words: words))
            == "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc1"
            + "9a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4")

        let key = try #require(SeedPhraseKey(words: words))
        #expect(Hex.string(key.privateKey) == "1ab42cc412b618bdea3a599e3c9bae199ebf030895b039e9db1e30dafb12b727")
        #expect(Hex.string(key.publicKeyPoint)
            == "0437b0bb7a8288d38ed49a524b5dc98cff3eb5ca824c9f9dc0dfdb3d9cd600f299"
            + "a6179912b7451c09896c4098eca7ce6b2e58330672795e847c4d6af44e024230")
        let address = try #require(EthereumAddress.from(publicKeyPoint: key.publicKeyPoint))
        #expect(EthereumAddress.checksummed(address) == "0x9858EfFD232B4033E47d90003D41EC34EcaEda94")
    }

    /// A 24-word phrase is longer than one hash block, which is its own path
    /// through the key stretching.
    @Test func derivesTheStandardTwentyFourWordWallet() throws {
        let words = try #require(Bip39.words(entropy: [UInt8](repeating: 0, count: 32)))
        #expect(words.count == 24)
        #expect(words.last == "art")
        let key = try #require(SeedPhraseKey(words: words))
        #expect(Hex.string(key.privateKey) == "1053fae1b3ac64f178bcc21026fd06a3f4544ec2f35338b001f02d1d8efa3d5f")
        let address = try #require(EthereumAddress.from(publicKeyPoint: key.publicKeyPoint))
        #expect(EthereumAddress.checksummed(address) == "0xF278cF59F82eDcf871d630F28EcC8056f25C1cdb")
    }

    @Test func refusesEntropyOfTheWrongLength() {
        #expect(Bip39.words(entropy: [UInt8](repeating: 0, count: 15)) == nil)
        #expect(Bip39.words(entropy: [UInt8](repeating: 0, count: 17)) == nil)
        #expect(Bip39.words(entropy: [UInt8](repeating: 0, count: 36)) == nil)
    }

    @Test func refusesKeysOutsideTheCurve() {
        #expect(SeedPhraseKey(privateKey: [UInt8](repeating: 0, count: 32)) == nil)
        #expect(SeedPhraseKey(privateKey: [UInt8](repeating: 0xFF, count: 32)) == nil)
        #expect(SeedPhraseKey(privateKey: [1, 2, 3]) == nil)
    }

    // MARK: - Shared with the firmware

    private let tagRandom = (0..<32).map { UInt8($0) }
    private let phoneRandom = (0x20..<0x40).map { UInt8($0) }

    /// The same inputs give the same bytes — and so the same words — in
    /// tolu_cold/cold_entropy.h, where they were also checked against an
    /// independent SHA-256.
    @Test func mixesEntropyLikeTheFirmware() throws {
        let mixed = try #require(EntropyMixer.mix(tag: tagRandom, phone: phoneRandom, byteCount: 32))
        #expect(Hex.string(mixed) == "838b30c94b4d5f89e3278e60db6afe4d32e9d2d9c4f9601bd0a4a53416219abb")

        let entropy = try #require(EntropyMixer.mix(tag: tagRandom, phone: phoneRandom, byteCount: 16))
        #expect(Bip39.words(entropy: entropy)?.joined(separator: " ")
            == "logic flower crane notable sting shaft milk vault general swap sauce orange")
    }

    /// Neither source alone decides the phrase.
    @Test func eitherSourceChangesTheResult() throws {
        let base = try #require(EntropyMixer.mix(tag: tagRandom, phone: phoneRandom, byteCount: 16))
        var otherTag = tagRandom
        otherTag[31] ^= 1
        var otherPhone = phoneRandom
        otherPhone[0] ^= 1
        #expect(EntropyMixer.mix(tag: otherTag, phone: phoneRandom, byteCount: 16) != base)
        #expect(EntropyMixer.mix(tag: tagRandom, phone: otherPhone, byteCount: 16) != base)
        // Swapping the two is not the same thing either.
        #expect(EntropyMixer.mix(tag: phoneRandom, phone: tagRandom, byteCount: 16) != base)
    }

    @Test func refusesAShortRandomSource() {
        #expect(EntropyMixer.mix(tag: [1, 2, 3], phone: phoneRandom, byteCount: 16) == nil)
        #expect(EntropyMixer.mix(tag: tagRandom, phone: [], byteCount: 16) == nil)
        #expect(EntropyMixer.mix(tag: tagRandom, phone: phoneRandom, byteCount: 33) == nil)
    }

    @Test func phoneRandomIsThirtyTwoFreshBytes() throws {
        let first = try #require(EntropyMixer.phoneRandom())
        let second = try #require(EntropyMixer.phoneRandom())
        #expect(first.count == EntropyMixer.sourceByteCount)
        #expect(first != second)
    }

    private let keySlot: [UInt8] = [0x12, 0x22, 0x22, 0x21]
    private let passwordSlot: [UInt8] = [0x12, 0x22, 0x22, 0x22]
    /// Sign, verify and read — what a wallet key is allowed.
    private let walletPolicy: UInt32 = 0x1820_0000

    /// Byte for byte what the firmware's `se05xImportKeyPair` sends for the
    /// same slots and the same key (printed from the firmware source).
    @Test func writesAKeyLikeTheFirmware() throws {
        let key = try #require(SeedPhraseKey(privateKey: (1...32).map { UInt8($0) }))
        let payload = KeyPairPayload.make(keyObjectID: keySlot, authObjectID: passwordSlot,
                                          policyMask: walletPolicy, importing: key)
        #expect(Hex.string(payload)
            == "1109" + "08" + "12222222" + "18200000"
            + "4104" + "12222221"
            + "420110"
            + "4320" + "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"
            + "4441" + "0484bf7562262bbd6940085748f3be6afa52ae317155181ece31b66351ccffa4b0"
            + "8cc43d63b2859d469fee15f31c9edb5324266e6fd0407e87382d60fc4511acd8")
    }

    /// With no key to store, the command asks the tag to make one — the
    /// bytes this app has always sent for a key generated in the tag.
    @Test func asksTheTagToGenerateWhenThereIsNoKey() {
        let payload = KeyPairPayload.make(keyObjectID: keySlot, authObjectID: passwordSlot, policyMask: walletPolicy)
        #expect(Hex.string(payload) == "1109" + "08" + "12222222" + "18200000" + "4104" + "12222221" + "420110")
    }
}
