//
//  Se05xTag+Prepare.swift
//  toluWallet
//
//  What a seed-phrase wallet asks the tag before any word is shown: whether a
//  slot is free, and random bytes from the chip's generator. Neither writes
//  anything, and neither needs a password session.
//

import Foundation

extension Se05xTag {

    /// True when an object already sits in this slot. Unlike the writer's
    /// own check, a tag that can't answer is an error here: words must not be
    /// handed out for a slot nobody could confirm is free.
    func objectExists(_ objectId: [UInt8]) async throws -> Bool {
        let response = try await transceive(cla: Se05x.cla, ins: Se05x.insMgmt,
                                            p1: Se05x.p1Default, p2: Se05x.p2Exist,
                                            data: Tlv.encode(Se05x.tag1, objectId),
                                            operation: "check slot")
        guard let result = Tlv.findValue(response, tag: Se05x.tag1)?.first else {
            throw Se05xError.apdu("check slot", 0, 0)
        }
        return result == Se05x.resultSuccess
    }

    /// `count` random bytes from the chip's generator (GetRandom).
    func random(count: Int) async throws -> [UInt8] {
        let size = [UInt8(truncatingIfNeeded: count >> 8), UInt8(truncatingIfNeeded: count)]
        let response = try await transceive(cla: Se05x.cla, ins: Se05x.insMgmt,
                                            p1: Se05x.p1Default, p2: Se05x.p2Random,
                                            data: Tlv.encode(Se05x.tag1, size),
                                            operation: "get random")
        guard let bytes = Tlv.findValue(response, tag: Se05x.tag1), bytes.count == count else {
            throw Se05xError.apdu("get random", 0, 0)
        }
        return bytes
    }
}
