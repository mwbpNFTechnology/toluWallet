//
//  Se05xTag+Provision.swift
//  toluWallet
//
//  Putting a wallet onto a tag: the curves, this iPhone's public key as an
//  ECKey authentication object, and the secp256k1 key bound to it. The
//  same bytes as tolu_cold sends for the same objects.
//

import Foundation

extension Se05xTag {

    /// CreateECCurve and its five parameters. A chip that already knows the
    /// curve refuses them, so status words are not checked — a dropped tap is.
    func prepareCurve(_ curve: EcCurve) async throws {
        _ = try await send(cla: Se05x.cla, ins: Se05x.insWrite, p1: Se05x.p1Curve, p2: Se05x.p2Create,
                           data: Tlv.encode(Se05x.tag1, [curve.id]))
        for parameter in curve.parameters {
            _ = try await send(cla: Se05x.cla, ins: Se05x.insWrite, p1: Se05x.p1Curve, p2: Se05x.p2Param,
                               data: Tlv.encode(Se05x.tag1, [curve.id])
                                   + Tlv.encode(Se05x.tag2, [parameter.selector])
                                   + Tlv.encode(Se05x.tag3, parameter.value))
        }
    }

    /// Whether `authObjectId` is free, already holds `publicKey`, or holds
    /// something else. Authentication objects can be read by anyone (their
    /// default policy), so this needs no session.
    func phoneKeySlot(_ authObjectId: [UInt8], publicKey: [UInt8]) async throws -> PhoneKeySlot {
        guard try await objectExists(authObjectId) else { return .free }
        let response = try? await transceive(cla: Se05x.cla, ins: Se05x.insRead,
                                             p1: Se05x.p1Default, p2: Se05x.p2Default,
                                             data: Tlv.encode(Se05x.tag1, authObjectId),
                                             operation: "read phone key")
        let stored = response.flatMap { Tlv.findValue($0, tag: Se05x.tag1) }
        return stored == publicKey ? .thisPhone : .taken
    }

    /// WriteECKey of this iPhone's public key as an authentication object:
    /// no attempt limit (a signature cannot be guessed) and the default
    /// policy, under which nobody may change or delete it.
    func writePhoneKey(_ authObjectId: [UInt8], publicKey: [UInt8]) async throws {
        try await transceive(cla: Se05x.cla, ins: Se05x.insWrite | Se05x.insAuthObject,
                             p1: Se05x.p1Public | Se05x.p1EC, p2: Se05x.p2Default,
                             data: PhoneKeyPayload.make(authObjectID: authObjectId, publicKey: publicKey),
                             operation: "write phone key")
    }

    /// WriteECKey of the wallet key, run inside the ECKey session: generated
    /// by the tag, or the given pair — which then crosses NFC encrypted.
    func writeWalletKey(_ keyObjectId: [UInt8], authObjectId: [UInt8], importing key: SeedPhraseKey?) async throws {
        try await execute(cla: Se05x.cla, ins: Se05x.insWrite,
                          p1: Se05x.p1KeyPair | Se05x.p1EC, p2: Se05x.p2Default,
                          data: KeyPairPayload.make(keyObjectID: keyObjectId, authObjectID: authObjectId,
                                                    policyMask: KeyPairPayload.walletPolicy, importing: key),
                          operation: "write key")
    }
}
