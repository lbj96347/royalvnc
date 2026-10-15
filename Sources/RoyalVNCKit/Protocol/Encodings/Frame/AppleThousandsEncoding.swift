import Foundation

extension VNCProtocol {
    final class AppleThousandsEncoding: VNCFrameEncoding {
        let encodingType: VNCEncodingType = 1002
        private let stream = ZlibStream()
        func decodeRectangle(_ rectangle: Rectangle, framebuffer: VNCFramebuffer,
                             connection: NetworkConnectionReading, logger: VNCLogger) async throws {
            let w = Int(rectangle.width), h = Int(rectangle.height)
            guard w > 0, h > 0 else { return }
            guard Int(rectangle.xPosition)+w <= Int(framebuffer.size.width),
                  Int(rectangle.yPosition)+h <= Int(framebuffer.size.height), w*h <= 33_554_432,
                  framebuffer.sourceProperties.bytesPerPixel == 4 else { throw AppleStandardError.invalidMessage }
            let count = Int(try await connection.readUInt32())
            guard (1...8_388_608).contains(count) else { throw AppleStandardError.invalidMessage }
            let compressed = try await connection.read(length: count)
            let words = try stream.decompressedData(compressedData: compressed, uncompressedSize: UInt(w*h*2))
            var bgra = Data(count: w*h*4)
            for i in 0..<w*h {
                let word = UInt16(words[i*2]) << 8 | UInt16(words[i*2+1])
                for channel in 0..<3 {
                    let value = UInt8((word >> (channel*5)) & 31)
                    bgra[i*4+channel] = (value << 3) | (value >> 2)
                }
                bgra[i*4+3] = 255
            }
            framebuffer.update(region: rectangle.region, data: &bgra)
            framebuffer.didUpdate(region: rectangle.region)
        }
    }
}
