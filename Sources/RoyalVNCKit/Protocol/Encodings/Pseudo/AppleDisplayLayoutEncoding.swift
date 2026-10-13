import Foundation

extension VNCProtocol {
    struct AppleDisplayLayoutEncoding: VNCReceivablePseudoEncoding {
        let encodingType: VNCEncodingType = 1105

        func receive(_ rectangle: VNCProtocol.Rectangle, framebuffer: VNCFramebuffer,
                     connection: NetworkConnectionReading, logger: VNCLogger) async throws {
            let length = try await connection.readUInt16()
            let payload = try await connection.read(length: Int(length))
            // Consume unsupported metadata without losing framing or retaining a stale main display.
            framebuffer.updateAppleDisplayLayout(VNCAppleDisplayLayout.parse(payload))
        }
    }
}
