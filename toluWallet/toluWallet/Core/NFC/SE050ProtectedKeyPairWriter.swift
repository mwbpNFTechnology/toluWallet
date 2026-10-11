//
//  SE050ProtectedKeyPairWriter.swift
//  toluWallet
//
//  Creates a password-protected secp256k1 key pair on a tag. Ported from
//  toluTag (which ported it from tolu). Two additions here:
//
//  - before writing, it checks that the key slot and the password slot are
//    both free, so a wallet is never bound to a password object that already
//    exists on the tag;
//  - it can write a key pair made outside the tag (a seed-phrase wallet)
//    instead of asking the tag to generate one. Everything else — the curve,
//    the password object, the policy — is the same either way.
//

import Foundation
import CoreNFC
import Combine

final class SE050ProtectedKeyPairWriter: NSObject, ObservableObject {

    @Published var status: String = "Ready to create protected key"
    @Published var isSessionActive: Bool = false
    @Published var isOperationSuccessful: Bool = false
    @Published var configuration: ProtectedKeyConfiguration?

    var onFinish: ((Result<ProtectedKeyConfiguration, Error>) -> Void)?

    private struct Constants {
        static let appletAID: [UInt8] = [0xA0,0x00,0x00,0x03,0x96,0x54,0x53,0x00,0x00,0x00,0x01,0x03,0x00,0x00,0x00,0x00]
        static let INS_WRITE: UInt8 = 0x01
        static let INS_READ: UInt8 = 0x02
        static let INS_MGMT: UInt8 = 0x04
        static let INS_AUTH_OBJECT: UInt8 = 0x40
        static let P1_DEFAULT: UInt8 = 0x00
        static let P1_EC: UInt8 = 0x01
        static let P1_KEY_PAIR: UInt8 = 0x60
        static let P1_USERID: UInt8 = 0x07
        static let P1_CURVE: UInt8 = 0x0B
        static let P2_DEFAULT: UInt8 = 0x00
        static let P2_CREATE: UInt8 = 0x04
        static let P2_PARAM: UInt8 = 0x40
        static let P2_EXIST: UInt8 = 0x27
        static let RESULT_SUCCESS: UInt8 = 0x01
        static let TAG_OBJECT_ID: UInt8 = 0x41
        static let TAG_VALUE: UInt8 = 0x42
        static let TAG_PARAM_VALUE: UInt8 = 0x43
        static let TAG_MAX_ATTEMPTS: UInt8 = 0x12
        static let CURVE_ID_SECP256K1: UInt8 = 0x10
        static let CURVE_PARAM_PRIME: UInt8 = 0x10
        static let CURVE_PARAM_A: UInt8 = 0x01
        static let CURVE_PARAM_B: UInt8 = 0x02
        static let CURVE_PARAM_G: UInt8 = 0x04
        static let CURVE_PARAM_N: UInt8 = 0x08
        static let CLA_NO_SM: UInt8 = 0x80
        static let CLA_ISO: UInt8 = 0x00
        static let POLICY_ALLOW_SIGN: UInt32 = 0x10000000
        static let POLICY_ALLOW_VERIFY: UInt32 = 0x08000000
        static let POLICY_ALLOW_READ: UInt32 = 0x00200000
        static let POLICY_ALLOW_DELETE: UInt32 = 0x00040000
        static let SECP256K1_PRIME = "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F"
        static let SECP256K1_A = "0000000000000000000000000000000000000000000000000000000000000000"
        static let SECP256K1_B = "0000000000000000000000000000000000000000000000000000000000000007"
        static let SECP256K1_G = "0479BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8"
        static let SECP256K1_N = "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141"
    }

    private var tagSession: NFCTagReaderSession?
    private var userIDValue = ""
    private var userIDObjectID = ""
    private var keyObjectID = ""
    private var maxAttempts = 0
    private var deletable = false
    private var usePin = true
    private var retrievedPublicKey: String?
    private var didFinish = false
    /// A key pair to write as it is, instead of having the tag generate one.
    private var importedKey: SeedPhraseKey?
    private var allowExistingPassword = false
    private var passwordObjectAlreadyOnTag = false

    /// What the tag acknowledged in the last run, readable after a failure:
    /// a tap that drops halfway may still have written something, and the
    /// next attempt has to know.
    private(set) var didWritePasswordObject = false
    private(set) var didWriteKey = false

    /// - Parameters:
    ///   - importing: a key pair to write instead of generating one in the tag.
    ///   - allowExistingPassword: accept a password object that is already in
    ///     its slot and bind the key to it — for a retry after this same run
    ///     wrote the password but not the key.
    func createProtectedKeyPair(userID: String, userIDObjectID: String, keyObjectID: String,
                                maxAttempts: Int = 0, deletable: Bool = false, usePin: Bool = true,
                                importing importedKey: SeedPhraseKey? = nil,
                                allowExistingPassword: Bool = false, alert: String) {
        isOperationSuccessful = false
        configuration = nil
        retrievedPublicKey = nil
        didFinish = false
        self.importedKey = importedKey
        self.allowExistingPassword = allowExistingPassword
        passwordObjectAlreadyOnTag = false
        didWritePasswordObject = false
        didWriteKey = false

        if usePin {
            guard userID.count >= 4 && userID.count <= 16 else {
                finishFailure(ProtectedKeyWriterError.invalidUserIDLength); return
            }
            guard userIDObjectID.count == 8, hexStringToBytes(userIDObjectID) != nil else {
                finishFailure(ProtectedKeyWriterError.invalidObjectIDFormat); return
            }
        }
        guard keyObjectID.count == 8, hexStringToBytes(keyObjectID) != nil else {
            finishFailure(ProtectedKeyWriterError.invalidObjectIDFormat); return
        }
        self.userIDValue = userID
        self.userIDObjectID = userIDObjectID
        self.keyObjectID = keyObjectID
        self.maxAttempts = maxAttempts
        self.deletable = deletable
        self.usePin = usePin

        guard NFCTagReaderSession.readingAvailable else {
            finishFailure(ProtectedKeyWriterError.noNFCTag); return
        }
        tagSession = NFCTagReaderSession(
            configuration: .init(pollingOption: .iso14443), delegate: self, queue: .main
        )
        tagSession?.alertMessage = alert
        tagSession?.begin()
        isSessionActive = true
        status = "Scanning for SE050 tag..."
    }

    private func hexStringToBytes(_ hex: String) -> [UInt8]? {
        var hex = hex
        if hex.hasPrefix("0x") { hex = String(hex.dropFirst(2)) }
        guard hex.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            let n = hex.index(i, offsetBy: 2)
            guard let b = UInt8(hex[i..<n], radix: 16) else { return nil }
            bytes.append(b); i = n
        }
        return bytes
    }

    private func fail(session: NFCTagReaderSession, error: ProtectedKeyWriterError) {
        status = error.localizedDescription
        isSessionActive = false
        session.invalidate(errorMessage: error.localizedDescription)
        finishFailure(error)
    }

    private func finishFailure(_ error: Error) {
        guard !didFinish else { return }
        didFinish = true
        importedKey = nil
        onFinish?(.failure(error))
    }
}

extension SE050ProtectedKeyPairWriter: NFCTagReaderSessionDelegate {
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) { isSessionActive = true }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        isSessionActive = false
        if !isOperationSuccessful { finishFailure(error) }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else { fail(session: session, error: .noNFCTag); return }
        session.connect(to: tag) { error in
            if let error = error { self.fail(session: session, error: .connectionError(error)); return }
            guard case let .iso7816(isoTag) = tag else { self.fail(session: session, error: .unsupportedTagType); return }
            self.selectApplet(tag: isoTag, session: session)
        }
    }
}

extension SE050ProtectedKeyPairWriter {
    private func selectApplet(tag: NFCISO7816Tag, session: NFCTagReaderSession) {
        status = "Selecting SE050 applet..."
        let apdu = NFCISO7816APDU(instructionClass: Constants.CLA_ISO, instructionCode: 0xA4,
                                  p1Parameter: 0x04, p2Parameter: 0x00,
                                  data: Data(Constants.appletAID), expectedResponseLength: 256)
        tag.sendCommand(apdu: apdu) { _, sw1, sw2, error in
            if error != nil || !(sw1 == 0x90 && sw2 == 0x00) {
                self.fail(session: session, error: .appletSelectionFailed); return
            }
            self.checkSlotsFree(tag: tag, session: session)
        }
    }

    /// Stops before anything is written if either slot is already taken.
    private func checkSlotsFree(tag: NFCISO7816Tag, session: NFCTagReaderSession) {
        status = "Checking the slots..."
        objectExists(keyObjectID, tag: tag) { keyExists in
            if keyExists { self.fail(session: session, error: .keySlotInUse); return }
            guard self.usePin else { self.initializeSecp256k1Curve(tag: tag, session: session); return }
            self.objectExists(self.userIDObjectID, tag: tag) { passwordExists in
                if passwordExists {
                    guard self.allowExistingPassword else {
                        self.fail(session: session, error: .passwordSlotInUse); return
                    }
                    self.passwordObjectAlreadyOnTag = true
                }
                self.initializeSecp256k1Curve(tag: tag, session: session)
            }
        }
    }

    /// CheckObjectExists. A tag that can't answer is treated as "free", so the
    /// write behaves exactly as it did before this check existed.
    private func objectExists(_ objectID: String, tag: NFCISO7816Tag, completion: @escaping (Bool) -> Void) {
        guard let idBytes = hexStringToBytes(objectID) else { completion(false); return }
        var data = Data([Constants.TAG_OBJECT_ID, UInt8(idBytes.count)]); data.append(contentsOf: idBytes)
        let apdu = NFCISO7816APDU(instructionClass: Constants.CLA_NO_SM, instructionCode: Constants.INS_MGMT,
                                  p1Parameter: Constants.P1_DEFAULT, p2Parameter: Constants.P2_EXIST,
                                  data: data, expectedResponseLength: 256)
        tag.sendCommand(apdu: apdu) { response, sw1, sw2, error in
            guard error == nil, sw1 == 0x90, sw2 == 0x00 else { completion(false); return }
            let bytes = [UInt8](response)
            // TLV[TAG_1] holding a one-byte result.
            let exists = bytes.count >= 3 && bytes[0] == Constants.TAG_OBJECT_ID
                && bytes[2] == Constants.RESULT_SUCCESS
            completion(exists)
        }
    }

    private func initializeSecp256k1Curve(tag: NFCISO7816Tag, session: NFCTagReaderSession) {
        status = "Initializing secp256k1 curve..."
        let data = Data([Constants.TAG_OBJECT_ID, 0x01, Constants.CURVE_ID_SECP256K1])
        let apdu = NFCISO7816APDU(instructionClass: Constants.CLA_NO_SM, instructionCode: Constants.INS_WRITE,
                                  p1Parameter: Constants.P1_CURVE, p2Parameter: Constants.P2_CREATE,
                                  data: data, expectedResponseLength: 256)
        tag.sendCommand(apdu: apdu) { _, _, _, _ in
            self.setCurveParameters(tag: tag, session: session)
        }
    }

    private func setCurveParameters(tag: NFCISO7816Tag, session: NFCTagReaderSession) {
        let params: [(UInt8, String)] = [
            (Constants.CURVE_PARAM_PRIME, Constants.SECP256K1_PRIME),
            (Constants.CURVE_PARAM_A, Constants.SECP256K1_A),
            (Constants.CURVE_PARAM_B, Constants.SECP256K1_B),
            (Constants.CURVE_PARAM_G, Constants.SECP256K1_G),
            (Constants.CURVE_PARAM_N, Constants.SECP256K1_N),
        ]
        setCurveParameter(tag: tag, session: session, parameters: params, index: 0)
    }

    private func setCurveParameter(tag: NFCISO7816Tag, session: NFCTagReaderSession, parameters: [(UInt8, String)], index: Int) {
        guard index < parameters.count else {
            if usePin && !passwordObjectAlreadyOnTag {
                createUserID(tag: tag, session: session)
            } else {
                writeKeyPair(tag: tag, session: session)
            }
            return
        }
        let (paramId, hex) = parameters[index]
        guard let valueBytes = hexStringToBytes(hex) else {
            setCurveParameter(tag: tag, session: session, parameters: parameters, index: index + 1); return
        }
        var data = Data()
        data.append(contentsOf: [Constants.TAG_OBJECT_ID, 0x01, Constants.CURVE_ID_SECP256K1])
        data.append(contentsOf: [Constants.TAG_VALUE, 0x01, paramId])
        data.append(Constants.TAG_PARAM_VALUE); data.append(UInt8(valueBytes.count)); data.append(contentsOf: valueBytes)
        let apdu = NFCISO7816APDU(instructionClass: Constants.CLA_NO_SM, instructionCode: Constants.INS_WRITE,
                                  p1Parameter: Constants.P1_CURVE, p2Parameter: Constants.P2_PARAM,
                                  data: data, expectedResponseLength: 256)
        tag.sendCommand(apdu: apdu) { _, _, _, _ in
            self.setCurveParameter(tag: tag, session: session, parameters: parameters, index: index + 1)
        }
    }

    private func createUserID(tag: NFCISO7816Tag, session: NFCTagReaderSession) {
        status = "Creating UserID..."
        guard let userIDObjectIDBytes = hexStringToBytes(userIDObjectID) else {
            fail(session: session, error: .invalidObjectIDFormat); return
        }
        var payload = Data()
        if maxAttempts > 0 {
            payload.append(contentsOf: [Constants.TAG_MAX_ATTEMPTS, 0x02, UInt8((maxAttempts >> 8) & 0xFF), UInt8(maxAttempts & 0xFF)])
        }
        payload.append(Constants.TAG_OBJECT_ID); payload.append(UInt8(userIDObjectIDBytes.count)); payload.append(contentsOf: userIDObjectIDBytes)
        let userIDData = userIDValue.data(using: .utf8)!
        payload.append(Constants.TAG_VALUE); payload.append(UInt8(userIDData.count)); payload.append(userIDData)
        let apdu = NFCISO7816APDU(instructionClass: Constants.CLA_NO_SM,
                                  instructionCode: Constants.INS_WRITE | Constants.INS_AUTH_OBJECT,
                                  p1Parameter: Constants.P1_USERID, p2Parameter: Constants.P2_DEFAULT,
                                  data: payload, expectedResponseLength: 256)
        tag.sendCommand(apdu: apdu) { _, sw1, sw2, error in
            // The slot was just checked to be free, so a refusal is real.
            // Going on regardless would create a key bound to a password
            // object that isn't there — a key nobody could ever use, in a
            // slot that can't be cleared.
            guard error == nil, sw1 == 0x90, sw2 == 0x00 else {
                self.fail(session: session, error: .passwordObjectRefused(sw1: sw1, sw2: sw2)); return
            }
            self.didWritePasswordObject = true
            self.writeKeyPair(tag: tag, session: session)
        }
    }

    private func writeKeyPair(tag: NFCISO7816Tag, session: NFCTagReaderSession) {
        status = importedKey == nil ? "Creating protected secp256k1 key pair..." : "Writing the key pair..."
        guard let keyObjectIDBytes = hexStringToBytes(keyObjectID) else {
            fail(session: session, error: .invalidObjectIDFormat); return
        }
        // Auth id the policy binds to: the UserID slot when PIN-protected, or all
        // zeros (the default session) when the key has no PIN.
        let authIdBytes: [UInt8] = usePin ? (hexStringToBytes(userIDObjectID) ?? [0, 0, 0, 0]) : [0, 0, 0, 0]
        var policyMask = Constants.POLICY_ALLOW_SIGN | Constants.POLICY_ALLOW_VERIFY | Constants.POLICY_ALLOW_READ
        if deletable { policyMask |= Constants.POLICY_ALLOW_DELETE }
        // With `importedKey` the tag stores exactly that pair; without it the
        // tag generates one.
        let data = Data(KeyPairPayload.make(keyObjectID: keyObjectIDBytes, authObjectID: authIdBytes,
                                            policyMask: policyMask, importing: importedKey))

        let apdu = NFCISO7816APDU(instructionClass: Constants.CLA_NO_SM, instructionCode: Constants.INS_WRITE,
                                  p1Parameter: Constants.P1_KEY_PAIR | Constants.P1_EC, p2Parameter: Constants.P2_DEFAULT,
                                  data: data, expectedResponseLength: 256)
        tag.sendCommand(apdu: apdu) { _, sw1, sw2, error in
            if error != nil { self.fail(session: session, error: .keyPairCreationFailed); return }
            guard sw1 == 0x90, sw2 == 0x00 else {
                self.fail(session: session, error: .keyRefused(sw1: sw1, sw2: sw2)); return
            }
            self.didWriteKey = true
            self.importedKey = nil
            self.readPublicKey(tag: tag, session: session)
        }
    }

    private func readPublicKey(tag: NFCISO7816Tag, session: NFCTagReaderSession) {
        status = "Reading public key..."
        guard let keyObjectIDBytes = hexStringToBytes(keyObjectID) else {
            fail(session: session, error: .invalidObjectIDFormat); return
        }
        var readData = Data([Constants.TAG_OBJECT_ID, 0x04]); readData.append(contentsOf: keyObjectIDBytes)
        let apdu = NFCISO7816APDU(instructionClass: Constants.CLA_NO_SM, instructionCode: Constants.INS_READ,
                                  p1Parameter: Constants.P1_DEFAULT, p2Parameter: Constants.P2_DEFAULT,
                                  data: readData, expectedResponseLength: 256)
        tag.sendCommand(apdu: apdu) { response, sw1, sw2, _ in
            let pk: String? = (sw1 == 0x90 && sw2 == 0x00) ? response.toHexString() : nil
            self.readUniqueId(tag: tag, session: session, publicKey: pk)
        }
    }

    /// Reads the chip's factory unique id (reserved object 0x7FFF0206) so the
    /// saved record can be tied to this specific card.
    private func readUniqueId(tag: NFCISO7816Tag, session: NFCTagReaderSession, publicKey: String?) {
        status = "Reading card id..."
        let reserved: [UInt8] = [0x7F, 0xFF, 0x02, 0x06]
        var readData = Data([Constants.TAG_OBJECT_ID, 0x04]); readData.append(contentsOf: reserved)
        let apdu = NFCISO7816APDU(instructionClass: Constants.CLA_NO_SM, instructionCode: Constants.INS_READ,
                                  p1Parameter: Constants.P1_DEFAULT, p2Parameter: Constants.P2_DEFAULT,
                                  data: readData, expectedResponseLength: 256)
        tag.sendCommand(apdu: apdu) { response, sw1, sw2, _ in
            var uid: String?
            if sw1 == 0x90 && sw2 == 0x00 {
                let bytes = [UInt8](response)
                // The value sits in a TLV whose length may be the long form
                // (0x41 0x82 0x00 0x12 …), so it has to be parsed, not sliced.
                let value = Tlv.findValue(bytes, tag: Constants.TAG_OBJECT_ID) ?? bytes
                uid = value.map { String(format: "%02X", $0) }.joined()
            }
            self.finalize(session: session, publicKey: publicKey, uniqueId: uid)
        }
    }

    private func finalize(session: NFCTagReaderSession, publicKey: String?, uniqueId: String?) {
        let config = ProtectedKeyConfiguration(userIDValue: userIDValue, userIDObjectID: userIDObjectID,
                                               keyObjectID: keyObjectID, maxAttempts: maxAttempts,
                                               publicKey: publicKey, uniqueId: uniqueId, createdDate: Date())
        configuration = config
        isOperationSuccessful = true
        status = "Protected key created successfully!"
        session.alertMessage = "Key on the tag ✓"
        session.invalidate()
        if !didFinish { didFinish = true; onFinish?(.success(config)) }
    }
}
