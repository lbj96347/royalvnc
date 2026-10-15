import Foundation
@_implementationOnly import CryptoSwift

/// One instance per direction. The owner serializes reads/writes and installs keys only at FBU boundaries.
/// Failures poison the channel; neither unverified plaintext nor a cleartext downgrade may escape.
final class AppleStandardRecords {
    private var key: [UInt8]
    private var iv: [UInt8]
    private var sequence: UInt64 = 0
    private var failed = false
    init(key: Data, iv: Data) throws {
        guard key.count == 16, iv.count == 16 else { throw AppleStandardError.invalidMessage }
        self.key = Array(key); self.iv = Array(iv)
    }
    func rekey(key: Data, iv: Data) throws {
        guard !failed, key.count == 16, iv.count == 16 else { throw AppleStandardError.integrity }
        self.key = Array(key); self.iv = Array(iv)
    }
    func seal(_ body: Data) throws -> Data {
        do {
            guard !failed, sequence <= UInt32.max, body.count <= 65498 else { throw AppleStandardError.integrity }
            var plain = AppleStandardWire.be(UInt16(body.count)) + body
            plain += Data(repeating: 0, count: (16 - (plain.count + 20) % 16) % 16)
            plain += Data((AppleStandardWire.be(UInt32(sequence)) + plain).sha1())
            let encrypted = try AES(key: key, blockMode: CBC(iv: iv), padding: .noPadding).encrypt(Array(plain))
            iv = Array(encrypted.suffix(16)); sequence += 1
            return AppleStandardWire.be(UInt16(encrypted.count)) + Data(encrypted)
        } catch { failed = true; throw error }
    }
    func open(_ ciphertext: Data) throws -> Data {
        do {
            guard !failed, sequence <= UInt32.max, ciphertext.count >= 32,
                  ciphertext.count <= 65520, ciphertext.count % 16 == 0 else { throw AppleStandardError.integrity }
            let plain = Data(try AES(key: key, blockMode: CBC(iv: iv), padding: .noPadding).decrypt(Array(ciphertext)))
            let signed = Data(plain.dropLast(20))
            let expected = Data((AppleStandardWire.be(UInt32(sequence)) + signed).sha1())
            let actual = Data(plain.suffix(20))
            var difference: UInt8 = 0
            for (a,b) in zip(expected, actual) { difference |= a ^ b }
            guard difference == 0 else { throw AppleStandardError.integrity }
            let count = Int(signed[0]) * 256 + Int(signed[1])
            guard count <= signed.count - 2, signed.count - 2 - count < 16 else { throw AppleStandardError.integrity }
            iv = Array(ciphertext.suffix(16)); sequence += 1
            return Data(signed.dropFirst(2).prefix(count))
        } catch { failed = true; throw error }
    }
    static func unwrap(_ payload: Data, key: Data) throws -> (Data, Data) {
        guard payload.count == 36, key.count == 16, AppleStandardWire.u32(payload, 0) == 1 else { throw AppleStandardError.invalidMessage }
        let cipher = try AES(key: Array(key), blockMode: ECB(), padding: .noPadding)
        return (Data(try cipher.decrypt(Array(payload[4..<20]))), Data(try cipher.decrypt(Array(payload[20..<36]))))
    }
}
