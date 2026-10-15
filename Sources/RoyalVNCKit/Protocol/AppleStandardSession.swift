import Foundation

/// Opt-in physical-desktop ARD session. These messages never request HP media or a virtual display.
/// Protocol references and interoperability boundaries are recorded in Docs/APPLE_STANDARD.md.
enum AppleStandardWire {
    static func be<T: FixedWidthInteger>(_ value: T) -> Data {
        var value = value.bigEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
    static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        data.dropFirst(offset).prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
    }
    static let encryptionRequest = Data([0x12,0,0,1,0,1,0,1,0,0,0,1])
    static let encryptionAck = Data([0x12,0,0,2,0,1,0,0])
    static let controlMode = Data([0x0a,0,0,1])
    static let disableClipboard = Data([0x15,0,0,0,0,0,0,0])
    static func display(_ id: UInt32?) -> Data {
        Data([0x0d, id == nil ? 1 : 0, 0, 0]) + be(id ?? 0)
    }
    static func automaticUpdates(width: UInt16, height: UInt16) -> Data {
        Data([9,0,0,1]) + be(UInt32(0)) + be(UInt16(0)) + be(UInt16(0)) + be(width) + be(height)
    }
    static func pointerMask(_ mask: UInt8) -> UInt8 {
        (mask & ~0x06) | ((mask & 4) >> 1) | ((mask & 2) << 1)
    }
    static func scroll(horizontal: Bool, delta: Int16, x: UInt16, y: UInt16) -> Data {
        let dx: Int16 = horizontal ? delta : 0
        let dy: Int16 = horizontal ? 0 : delta
        var compact = Data([0x17,0,0,32,0,2,0,8])
        compact += be(Float(dx).bitPattern) + be(Float(dy).bitPattern) + be(UInt32(0)) + be(UInt32(1))
        compact += Data(repeating: 0, count: 8) + be(x) + be(y)
        var detailed = Data([0x17,0,0,54,0,1,0,11])
        detailed += be(dx) + be(dy) + be(Int16(0))
        detailed += be(Int32(dx)*65536) + be(Int32(dy)*65536) + be(Int32(0))
        detailed += be(Int32(dx)*45) + be(Int32(dy)*45) + be(Int32(0))
        detailed += Data(repeating: 0, count: 16) + be(x) + be(y)
        return compact + detailed
    }
    static var viewerInfo: Data {
        var bitmap = Data(repeating: 0, count: 32)
        // Only basic control/status messages; clipboard/drag/media capabilities are not requested.
        bitmap[0] = 0x80
        return Data([0x21,0,0,62,0,1]) + be(UInt32(2)) +
            be(UInt32(6)) + be(UInt32(1)) + be(UInt32(0)) +
            be(UInt32(14)) + be(UInt32(0)) + be(UInt32(0)) + bitmap
    }
    static func physicalSession(info: Data) throws -> Data {
        guard info.count >= 10, info.count <= 4096 else { throw AppleStandardError.invalidMessage }
        let allowed = u32(info, 2)
        let user = Data(info.dropFirst(10).prefix { $0 != 0 })
        guard user.count <= 63 else { throw AppleStandardError.invalidMessage }
        // Never choose command 2 (a separate/virtual desktop).
        let command: UInt8 = allowed & 2 != 0 ? 1 : (user.isEmpty && allowed & 1 != 0 ? 0 : 255)
        guard command != 255 else { throw AppleStandardError.physicalDesktopUnavailable }
        return be(UInt16(72)) + be(UInt16(1)) + be(UInt32(0)) + Data([command,0]) + user + Data(repeating: 0, count: 64-user.count)
    }
}

public enum AppleStandardError: Error, LocalizedError {
    case unsupportedServer, physicalDesktopUnavailable, invalidMessage, integrity, encryptionRequired
    public var errorDescription: String? {
        switch self {
        case .unsupportedServer: "The Mac does not offer the experimental Apple Standard protocol."
        case .physicalDesktopUnavailable: "The Mac did not permit access to its physical desktop."
        case .invalidMessage: "The experimental Apple Standard session received an unsupported or malformed message."
        case .integrity: "Apple Standard encrypted session verification failed."
        case .encryptionRequired: "The Mac did not establish Apple Standard session encryption."
        }
    }
}

final class AppleStandardSession {
    var authKey: Data?
    var pendingRekey: Data?
    var needsRearm = false
    var cursors: [UInt32: VNCCursor] = [:]
    var cursorBytes = 0
    var currentCursor: VNCCursor = .empty
}

struct AppleStandardMessage: VNCSendableMessage {
    let data: Data
    var messageType: UInt8 { data.first ?? 0 }
    func send(connection: NetworkConnectionWriting) async throws { try await connection.write(data: data) }
}
