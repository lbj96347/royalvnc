import Foundation

extension VNCProtocol {
    /// Experimental Apple stream scaling. This does not change the physical display mode.
    struct AppleServerScale: VNCSendableMessage {
        let messageType: UInt8 = 8
        let scale: Double
        var data: Data {
            var bits = scale.bitPattern.bigEndian
            return Data([0x08, 0]) + withUnsafeBytes(of: &bits) { Data($0) }
        }
        func send(connection: NetworkConnectionWriting) async throws {
            try await connection.write(data: data)
        }
    }
}
