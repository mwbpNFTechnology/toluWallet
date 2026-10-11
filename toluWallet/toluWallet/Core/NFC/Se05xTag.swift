//
//  Se05xTag.swift
//  toluWallet
//
//  A connected SE05x tag: the low-level APDU transport, applet selection, and an
//  optional authenticated UserID/PIN session. Once a session is open, every read
//  is automatically wrapped in a ProcessSessionCmd so PIN-protected objects can
//  be read. High-level operations are in the +Read / +Write extensions.
//

import CoreNFC
import Foundation

final class Se05xTag {
    let tag: NFCISO7816Tag
    private(set) var sessionId: [UInt8]?

    var hasSession: Bool { sessionId != nil }

    init(_ tag: NFCISO7816Tag) {
        self.tag = tag
    }

    /// Selects the SE05x IoT applet. Must be called before any other command.
    func selectApplet() async throws {
        _ = try await transceive(cla: 0x00, ins: 0xA4, p1: 0x04, p2: 0x00,
                                 data: Se05x.aid, operation: "select applet")
    }

    /// Opens an authenticated session against a UserID and verifies its PIN.
    /// Afterwards `execute` wraps commands so protected objects can be read.
    func openUserIdSession(userObjectId: [UInt8], pin: [UInt8]) async throws {
        let response = try await transceive(cla: Se05x.cla, ins: Se05x.insMgmt,
                                            p1: Se05x.p1Default, p2: Se05x.p2SessionCreate,
                                            data: Tlv.encode(Se05x.tag1, userObjectId),
                                            operation: "create session")
        guard let session = Tlv.findValue(response, tag: Se05x.tag1), session.count == 8 else {
            throw Se05xError.apdu("create session", 0, 0)
        }
        sessionId = session
        _ = try await execute(cla: Se05x.cla, ins: Se05x.insMgmt,
                              p1: Se05x.p1Default, p2: Se05x.p2SessionUserId,
                              data: Tlv.encode(Se05x.tag1, pin),
                              operation: "verify pin")
    }

    /// Runs a command, wrapping it in a ProcessSessionCmd when a session is open.
    /// Read operations use this so they work with or without a PIN.
    @discardableResult
    func execute(cla: UInt8, ins: UInt8, p1: UInt8, p2: UInt8,
                 data: [UInt8], operation: String) async throws -> [UInt8] {
        guard let sessionId else {
            return try await transceive(cla: cla, ins: ins, p1: p1, p2: p2, data: data, operation: operation)
        }
        let inner = Self.apduBytes(cla: cla, ins: ins, p1: p1, p2: p2, data: data)
        let payload = Tlv.encode(Se05x.tagSessionId, sessionId) + Tlv.encode(Se05x.tag1, inner)
        let response = try await transceive(cla: Se05x.cla, ins: Se05x.insProcess,
                                            p1: Se05x.p1Default, p2: Se05x.p2Default,
                                            data: payload, operation: operation)
        return Tlv.findValue(response, tag: Se05x.tag1) ?? response
    }

    /// Sends one raw APDU and returns its response data, throwing on a non-0x9000
    /// status word.
    @discardableResult
    func transceive(cla: UInt8, ins: UInt8, p1: UInt8, p2: UInt8,
                    data: [UInt8], operation: String) async throws -> [UInt8] {
        let apdu = NFCISO7816APDU(
            instructionClass: cla, instructionCode: ins,
            p1Parameter: p1, p2Parameter: p2,
            data: Data(data), expectedResponseLength: 256
        )
        let (response, sw1, sw2): (Data, UInt8, UInt8) = try await withCheckedThrowingContinuation { continuation in
            tag.sendCommand(apdu: apdu) { responseData, sw1, sw2, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (responseData, sw1, sw2))
                }
            }
        }
        guard sw1 == Se05x.swSuccessHigh, sw2 == Se05x.swSuccessLow else {
            throw Se05xError.apdu(operation, sw1, sw2)
        }
        return [UInt8](response)
    }

    /// Builds the raw bytes of an inner command APDU (header, Lc, data, Le=256).
    private static func apduBytes(cla: UInt8, ins: UInt8, p1: UInt8, p2: UInt8, data: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [cla, ins, p1, p2]
        if !data.isEmpty {
            out.append(UInt8(data.count))
            out += data
        }
        out.append(0x00) // Le
        return out
    }
}
