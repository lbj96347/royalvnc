import Foundation

extension VNCProtocol {
    struct AppleStandardMetadataEncoding: VNCReceivablePseudoEncoding {
        let encodingType: VNCEncodingType
        let session: AppleStandardSession
        let layout: (Data) -> Void
        func receive(_ rectangle: Rectangle, framebuffer: VNCFramebuffer,
                     connection: NetworkConnectionReading, logger: VNCLogger) async throws {
            switch encodingType.rawValue {
            case 1103:
                guard session.pendingRekey == nil else { throw AppleStandardError.invalidMessage }
                session.pendingRekey = try await connection.read(length: 36)
            case 1105:
                let size = Int(try await connection.readUInt16())
                layout(try await connection.read(length: size))
            case 1104:
                let id = try await connection.readUInt32()
                let size = Int(try await connection.readUInt32())
                let w = Int(rectangle.width), h = Int(rectangle.height)
                guard size <= 1_048_576, w <= 512, h <= 512 else { throw AppleStandardError.invalidMessage }
                if size > 0 {
                    guard w > 0, h > 0, rectangle.xPosition < rectangle.width,
                          rectangle.yPosition < rectangle.height else { throw AppleStandardError.invalidMessage }
                    let compressed = try await connection.read(length: size)
                    let pixels = try ZlibStream().decompressedData(compressedData: compressed, uncompressedSize: UInt(w*h*5))
                    var rgba = Data(count: w*h*4)
                    for i in 0..<w*h {
                        rgba[i*4] = pixels[i*4+2]; rgba[i*4+1] = pixels[i*4+1]
                        rgba[i*4+2] = pixels[i*4]; rgba[i*4+3] = pixels[w*h*4+i]
                    }
                    let oldSize = session.cursors[id]?.imageData.count ?? 0
                    guard session.cursorBytes - oldSize + rgba.count <= 16_777_216,
                          session.cursors[id] != nil || session.cursors.count < 256 else { throw AppleStandardError.invalidMessage }
                    let cursor = VNCCursor(imageData: rgba, size: rectangle.region.size,
                        hotspot: rectangle.region.location, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerPixel: 4)
                    session.cursorBytes += rgba.count - oldSize
                    session.cursors[id] = cursor; session.currentCursor = cursor
                    framebuffer.updateCursor(cursor)
                } else if let cursor = session.cursors[id] {
                    session.currentCursor = cursor; framebuffer.updateCursor(cursor)
                }
            default: throw AppleStandardError.invalidMessage
            }
        }
    }
}
