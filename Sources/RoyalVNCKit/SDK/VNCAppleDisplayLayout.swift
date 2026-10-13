import Foundation

/// Apple's physical-display layout (pseudo-encoding 1105). Coordinates are backing pixels
/// within the combined framebuffer, not desktop points or Cocoa screen coordinates.
public struct VNCAppleDisplayLayout: Equatable, Sendable {
    public struct Display: Equatable, Sendable {
        public let id: UInt32
        public let x: Int
        public let y: Int
        public let width: Int
        public let height: Int
        public let flags: UInt32
        public var isMain: Bool { flags & 1 != 0 }
    }

    public let width: Int
    public let height: Int
    public let displays: [Display]

    /// Payload excludes the UInt16 length prefix. Only the observed version-5, 20-byte
    /// header / 56-byte display-record format is supported. Unknown layouts fail closed.
    /// See https://github.com/renegadelink/iShareScreen/blob/main/src/isharescreen/proxy/protocol/rfb.py
    public static func parse(_ payload: Data) -> Self? {
        let bytes = [UInt8](payload)
        guard bytes.count >= 20 else { return nil }
        func u16(_ offset: Int) -> Int { Int(bytes[offset]) << 8 | Int(bytes[offset + 1]) }
        func u32(_ offset: Int) -> UInt32 {
            bytes[offset..<offset + 4].reduce(0) { ($0 << 8) | UInt32($1) }
        }
        guard u16(0) == 5 else { return nil }
        let width = u16(6), height = u16(8), count = u16(18)
        guard width > 0, height > 0, count > 0, count <= 255,
              bytes.count >= 20 + count * 56 else { return nil }
        var displays: [Display] = []
        for index in 0..<count {
            let offset = 20 + index * 56
            // Apple uses QuickDraw rectangles: top, left, bottom, right (not x,y,w,h).
            let y = u16(offset + 28), x = u16(offset + 30)
            let bottom = u16(offset + 32), right = u16(offset + 34)
            guard right > x, bottom > y, right <= width, bottom <= height else { return nil }
            let id = u32(offset + 16)
            guard !displays.contains(where: { $0.id == id }) else { return nil }
            displays.append(Display(id: id, x: x, y: y, width: right - x,
                                    height: bottom - y, flags: u32(offset + 36)))
        }
        return Self(width: width, height: height, displays: displays)
    }
}
