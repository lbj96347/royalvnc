#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension VNCProtocol {
	struct ServerInit {
		let framebufferWidth: UInt16
		let framebufferHeight: UInt16

		let pixelFormat: PixelFormat

		let name: String
        var appleFlags: UInt32 = 0
	}
}

extension VNCProtocol.ServerInit {
	static func receive(connection: NetworkConnectionReading,
						isTightSecurityEnabled: Bool, appleStandard: Bool = false) async throws -> Self {
		guard !isTightSecurityEnabled else {
			// TODO: When Tight Security is enabled there are addtional fields
			// See https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst#serverinit
			throw VNCError.protocol(.notImplemented(feature: "Tight Security"))
		}

		let frameBufferWidth = try await connection.readUInt16()
		let frameBufferHeight = try await connection.readUInt16()

		let pixelFormat = try await VNCProtocol.PixelFormat.receive(connection: connection)

        let nameLength = Int(try await connection.readUInt32())
        guard nameLength <= 65535 else { throw VNCError.protocol(.invalidData) }
        let rawName = try await connection.read(length: nameLength)
        if !appleStandard, String(data: rawName, encoding: .utf8) == nil { throw VNCError.protocol(.invalidData) }
        var flags: UInt32 = 0
        var name = String(data: rawName.prefix { $0 != 0 }, encoding: .utf8) ?? ""
        if appleStandard, rawName.first == 0 {
            guard rawName.count >= 22 else { throw AppleStandardError.invalidMessage }
            flags = AppleStandardWire.u32(rawName, 2)
            name = String(data: rawName.dropFirst(22).split(separator: 0).last ?? Data.SubSequence(), encoding: .utf8) ?? "Mac"
        }

		return .init(framebufferWidth: frameBufferWidth,
					 framebufferHeight: frameBufferHeight,
					 pixelFormat: pixelFormat,
					 name: name, appleFlags: flags)
	}
}
