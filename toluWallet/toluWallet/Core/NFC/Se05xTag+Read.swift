//
//  Se05xTag+Read.swift
//  toluWallet
//
//  Read operations the wallet needs: the chip's unique id and a key's public
//  point. Trimmed from toluTag's read extension. Both go through `execute`, so
//  they work inside a password session.
//

import Foundation

extension Se05xTag {

    /// The chip's factory unique identifier, as `0x`-prefixed hex.
    func readUniqueId() async throws -> String {
        let response = try await execute(cla: Se05x.cla, ins: Se05x.insRead,
                                         p1: Se05x.p1Default, p2: Se05x.p2Default,
                                         data: Tlv.encode(Se05x.tag1, Se05x.reservedUniqueId),
                                         operation: "read unique id")
        let value = Tlv.findValue(response, tag: Se05x.tag1) ?? response
        var hex = Hex.string(value)
        if hex.count < 40 { hex = String(repeating: "0", count: 40 - hex.count) + hex }
        return "0x" + hex
    }

    /// The uncompressed public key (`0x04 || X || Y`, 65 bytes) of a key pair.
    func readPublicKeyPoint(objectId: [UInt8]) async throws -> [UInt8] {
        let response = try await execute(cla: Se05x.cla, ins: Se05x.insRead,
                                         p1: Se05x.p1Default, p2: Se05x.p2Default,
                                         data: Tlv.encode(Se05x.tag1, objectId),
                                         operation: "read public key")
        var i = 0
        while i + 65 <= response.count {
            if response[i] == 0x04 { return Array(response[i..<i + 65]) }
            i += 1
        }
        throw Se05xError.noKey
    }
}
