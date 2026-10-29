//
//  EcCurve.swift
//  toluWallet
//
//  The two curves a wallet tag has to know: secp256k1 for the wallet key,
//  NIST P-256 for the iPhone's key that unlocks it. The chip is told a
//  curve with CreateECCurve and five SetECCurveParam commands.
//

import Foundation

nonisolated struct EcCurve: Sendable {
    let id: UInt8
    /// SetECCurveParam selector and value, in the order they are sent.
    let parameters: [(selector: UInt8, value: [UInt8])]

    static let secp256k1 = EcCurve(
        id: Se05x.curveIdSecp256k1,
        prime: "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F",
        a: "0000000000000000000000000000000000000000000000000000000000000000",
        b: "0000000000000000000000000000000000000000000000000000000000000007",
        generator: "0479BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"
            + "483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8",
        order: "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141"
    )

    static let nistP256 = EcCurve(
        id: Se05x.curveIdNistP256,
        prime: "FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF",
        a: "FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFC",
        b: "5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B",
        generator: "046B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296"
            + "4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5",
        order: "FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551"
    )

    private init(id: UInt8, prime: String, a: String, b: String, generator: String, order: String) {
        self.id = id
        // Fixed, known-good hex: a failure here is a typo, caught by the tests.
        parameters = [(0x10, prime), (0x01, a), (0x02, b), (0x04, generator), (0x08, order)]
            .map { (selector: $0.0, value: Hex.bytes($0.1) ?? []) }
    }
}
