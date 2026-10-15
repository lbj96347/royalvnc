#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension VNCProtocol {
	struct FramebufferUpdate: VNCReceivableMessage {
		static let messageType: UInt8 = 0

		let messageType: UInt8
		let rectangles: [VNCProtocol.Rectangle]
        let encodingBytes: [Int64: UInt64]
	}
}

extension VNCProtocol.FramebufferUpdate {
	static func receive(connection: NetworkConnectionReading,
						framebuffer: VNCFramebuffer,
						encodings: Encodings,
						logger: VNCLogger,
                        currentFramebuffer: (() -> VNCFramebuffer?)? = nil,
                        didDecodePixelRectangle: ((VNCFramebuffer, VNCRegion) -> Void)? = nil,
                        willDecodePixelRectangle: (() -> Void)? = nil) async throws -> Self {
		try await connection.readPadding()
		let numberOfRectangles = try await connection.readUInt16()

		logger.logDebug("Got \(numberOfRectangles) rectangles to read from framebuffer update")

#if DEBUG
		if numberOfRectangles == 65535 {
			logger.logDebug("Likely encountered a framebuffer update with LastRect")
		}
#endif

		var rectangles = [VNCProtocol.Rectangle]()
        var encodingBytes: [Int64: UInt64] = [:]
        
        var activeFramebuffer = framebuffer
        activeFramebuffer.beginBatchUpdates()
        
        defer {
            activeFramebuffer.endBatchUpdates()
        }

		for idx in 0..<numberOfRectangles {
			logger.logDebug("Reading rectangle header \(idx + 1)/\(numberOfRectangles)")

			let startBytes = (connection as? CountingNetworkConnection)?.receivedByteCount ?? 0
            let rectangle = try await VNCProtocol.Rectangle.receive(connection: connection)
            defer {
                let endBytes = (connection as? CountingNetworkConnection)?.receivedByteCount ?? startBytes
                encodingBytes[Int64(rectangle.encodingType), default: 0] += endBytes - startBytes
            }

			logger.logDebug("Got rectangle header \(idx + 1)/\(numberOfRectangles): \(rectangle)")

			let encodingType = rectangle.encodingType

			guard let encoding = encodings[.init(encodingType)] else {
				throw VNCError.protocol(.unsupportedEncoding(encodingType: .init(encodingType)))
			}

			if let frameEncoding = encoding as? VNCFrameEncoding {
				logger.logDebug("Decoding frame rectangle \(idx + 1)/\(numberOfRectangles)")

                willDecodePixelRectangle?()
				try await frameEncoding.decodeRectangle(rectangle,
														framebuffer: activeFramebuffer,
														connection: connection,
														logger: logger)

				logger.logDebug("Finished decoding frame rectangle \(idx + 1)/\(numberOfRectangles)")

                let changed = (frameEncoding as? VNCProtocol.AppleMVSEncoding)?.changedPixels ?? true
                if changed, rectangle.width > 0, rectangle.height > 0,
                   Int(rectangle.xPosition) + Int(rectangle.width) <= Int(activeFramebuffer.size.width),
                   Int(rectangle.yPosition) + Int(rectangle.height) <= Int(activeFramebuffer.size.height) {
                    didDecodePixelRectangle?(activeFramebuffer,
                        VNCRegion(location: .init(x: rectangle.xPosition, y: rectangle.yPosition),
                                  size: .init(width: rectangle.width, height: rectangle.height)))
                }
                if changed { rectangles.append(rectangle) }
			} else if let pseudoEncoding = encoding as? VNCPseudoEncoding {
				if pseudoEncoding as? VNCProtocol.LastRectEncoding != nil {
					break
				} else if let receivablePseudoEncoding = pseudoEncoding as? VNCReceivablePseudoEncoding {
					logger.logDebug("Decoding pseudo rectangle \(idx + 1)/\(numberOfRectangles)")

					try await receivablePseudoEncoding.receive(rectangle,
														   framebuffer: activeFramebuffer,
															   connection: connection,
														   logger: logger)

                    // A resize replaces the surface. Remaining rectangles in this same
                    // update must target the new surface, including its layout metadata.
                    if let replacement = currentFramebuffer?(), replacement !== activeFramebuffer {
                        activeFramebuffer.endBatchUpdates()
                        activeFramebuffer = replacement
                        activeFramebuffer.beginBatchUpdates()
                        rectangles.removeAll()
                    }

					logger.logDebug("Finished decoding pseudo rectangle \(idx + 1)/\(numberOfRectangles)")
				} else {
					throw VNCError.protocol(.notImplemented(feature: "Pseudo Encoding: \(pseudoEncoding.encodingType)"))
				}
			}
		}

		return .init(messageType: Self.messageType,
					 rectangles: rectangles, encodingBytes: encodingBytes)
	}
}
