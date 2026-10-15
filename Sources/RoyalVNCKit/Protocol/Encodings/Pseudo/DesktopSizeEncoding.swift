#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension VNCProtocol {
	struct DesktopSizeEncoding: VNCReceivablePseudoEncoding {
		let encodingType = VNCPseudoEncodingType.desktopSize.rawValue
        var maximumPixels: Int? = nil
	}
}

extension VNCProtocol.DesktopSizeEncoding {
	func receive(_ rectangle: VNCProtocol.Rectangle,
				 framebuffer: VNCFramebuffer,
				 connection: NetworkConnectionReading,
				 logger: VNCLogger) async throws {
        let newSize = rectangle.region.size
        if let maximumPixels {
            guard newSize.width > 0, newSize.height > 0, newSize.width <= 16384, newSize.height <= 16384,
                  Int(newSize.width) * Int(newSize.height) <= maximumPixels else { throw AppleStandardError.invalidMessage }
        }

		framebuffer.resize(to: newSize)
	}
}
