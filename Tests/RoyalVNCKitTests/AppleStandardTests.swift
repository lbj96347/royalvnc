import Foundation
import XCTest
import CryptoSwift
@testable import RoyalVNCKit

final class AppleStandardTests: XCTestCase {
    private let key = Data(0..<16)
    private let iv = Data(16..<32)
    func testRecordsRoundTripAcrossMultipleMessagesAndRejectTamperingAndReplay() throws {
        let sender = try AppleStandardRecords(key: key, iv: iv)
        let receiver = try AppleStandardRecords(key: key, iv: iv)
        for body in [Data([4,1,0,0,0,0,0,65]), Data(repeating: 23, count: 65498), Data([9,0,0,1])] {
            let record = try sender.seal(body)
            XCTAssertEqual(try receiver.open(Data(record.dropFirst(2))), body)
        }
        let record = try AppleStandardRecords(key: key, iv: iv).seal(Data([5,0,0,1,0,2]))
        let replayReceiver = try AppleStandardRecords(key: key, iv: iv)
        _ = try replayReceiver.open(Data(record.dropFirst(2)))
        XCTAssertThrowsError(try replayReceiver.open(Data(record.dropFirst(2))))
        let corruptReceiver = try AppleStandardRecords(key: key, iv: iv)
        var corrupt = Data(record.dropFirst(2)); corrupt[corrupt.count-1] ^= 1
        XCTAssertThrowsError(try corruptReceiver.open(corrupt))
        XCTAssertThrowsError(try corruptReceiver.open(Data(record.dropFirst(2))), "Channel must remain poisoned")
    }
    func testRecordsValidateLengthsAndUnwrapSessionKeys() throws {
        let wrap = try AES(key: Array(key), blockMode: ECB(), padding: .noPadding)
        let payload = AppleStandardWire.be(UInt32(1)) + Data(try wrap.encrypt(Array(key))) + Data(try wrap.encrypt(Array(iv)))
        let result = try AppleStandardRecords.unwrap(payload, key: key)
        XCTAssertEqual(result.0, key); XCTAssertEqual(result.1, iv)
        XCTAssertThrowsError(try AppleStandardRecords.unwrap(Data(payload.dropFirst()), key: key))
        let invalid = try AppleStandardRecords(key: key, iv: iv)
        XCTAssertThrowsError(try invalid.open(Data(repeating: 0, count: 17)))
        XCTAssertThrowsError(try AppleStandardRecords(key: key, iv: iv).seal(Data(repeating: 0, count: 65499)))
    }
    func testPhysicalSessionSelectionNeverChoosesVirtualDisplay() throws {
        let console = Data([0,1]) + AppleStandardWire.be(UInt32(6)) + Data(repeating: 0, count: 4) + Data("fixture\0".utf8)
        let message = try AppleStandardWire.physicalSession(info: console)
        XCTAssertEqual(message.count, 74); XCTAssertEqual(message[8], 1)
        let login = Data([0,1]) + AppleStandardWire.be(UInt32(1)) + Data(repeating: 0, count: 5)
        XCTAssertEqual(try AppleStandardWire.physicalSession(info: login)[8], 0)
        let virtualOnly = Data([0,1]) + AppleStandardWire.be(UInt32(4)) + Data(repeating: 0, count: 5)
        XCTAssertThrowsError(try AppleStandardWire.physicalSession(info: virtualOnly))
        XCTAssertThrowsError(try AppleStandardWire.physicalSession(info: Data()))
    }
    func testPushSubscriptionAndEncodingListCannotStartHighPerformance() throws {
        XCTAssertEqual(AppleStandardWire.automaticUpdates(width: 640, height: 480),
                       Data([9,0,0,1,0,0,0,0,0,0,0,0,2,128,1,224]))
        XCTAssertEqual(AppleStandardWire.viewerInfo.count, 66)
        let settings = VNCConnection.Settings(isDebugLoggingEnabled: false, hostname: "localhost", port: 5900,
            isShared: true, isScalingEnabled: false, useDisplayLink: false, inputMode: .none,
            isClipboardRedirectionEnabled: false, colorDepth: .depth24Bit,
            frameEncodings: [.appleMVS,.appleThousands,.zlib,.zrle], isAppleStandardEnabled: true)
        let client = VNCConnection(settings: settings)
        let encodings = try client.orderedEncodingTypes().map(\.rawValue)
        XCTAssertEqual(Array(encodings.prefix(4)), [1011,1002,6,16])
        XCTAssertFalse(encodings.contains(1010)); XCTAssertFalse(encodings.contains(1110))
        XCTAssertFalse(encodings.contains(-313))
    }
}

extension AppleStandardTests {
    func testZeroSizedLoginDesktopRequestsPixelsAfterDesktopSize() async throws {
        let wire = SyntheticAppleWire(initiallyZeroSized: true)
        let client = VNCConnection(settings: .init(isDebugLoggingEnabled: false, hostname: "fixture", port: 5900,
            isShared: true, isScalingEnabled: false, useDisplayLink: false,
            inputMode: .none, isClipboardRedirectionEnabled: false,
            colorDepth: .depth24Bit, frameEncodings: [.zlib,.zrle], isAppleStandardEnabled: true))
        let delegate = SyntheticAppleDelegate()
        client.delegate = delegate
        client.connection = CountingNetworkConnection(base: wire)
        try await client.handshake()
        XCTAssertEqual(client.state.framebufferWidth, 0)
        try await client.finishAppleStandardEncryption()
        try await client.sendFramebufferUpdateRequest()
        XCTAssertEqual(client.state.framebufferWidth, 2)
        XCTAssertEqual(client.state.framebufferHeight, 1)
        XCTAssertGreaterThan(wire.subscriptions, 0)
        XCTAssertGreaterThan(wire.fullRequests, 0)
        try await client.receive()
        XCTAssertEqual(delegate.pixelUpdates, 1)
    }

    func testFragmentedEnhancedLoginEncryptionPushPixelsAndInputWithoutPolling() async throws {
        let wire = SyntheticAppleWire()
        let client = VNCConnection(settings: .init(isDebugLoggingEnabled: false, hostname: "fixture", port: 5900,
            isShared: true, isScalingEnabled: false, useDisplayLink: false,
            inputMode: .forwardKeyboardShortcutsIfNotInUseLocally, isClipboardRedirectionEnabled: false,
            colorDepth: .depth24Bit, frameEncodings: [.zlib,.zrle], isAppleStandardEnabled: true))
        let delegate = SyntheticAppleDelegate()
        client.delegate = delegate
        client.connection = CountingNetworkConnection(base: wire)
        try await client.handshake()
        XCTAssertEqual(wire.clientInit, 0xc1)
        try await client.finishAppleStandardEncryption()
        XCTAssertTrue(client.isAppleStandardEncrypted)
        try await client.sendFramebufferUpdateRequest()
        try await client.receive()
        XCTAssertEqual(client.framebuffer?.size, VNCSize(width: 2, height: 1))
        XCTAssertEqual(delegate.pixelUpdates, 1)
        let requests = wire.fullRequests
        try await client.sendFramebufferUpdateRequest()
        XCTAssertEqual(wire.fullRequests, requests, "Push updates must not re-enter sequential polling")
        // Input shares the verified transport, including a record split across tiny reads.
        try await client.connection.write(data: Data([4,1,0,0,0,0,0,65]))
        XCTAssertEqual(wire.receivedInput, Data([4,1,0,0,0,0,0,65]))
        let subscriptions = wire.subscriptions
        try wire.enqueueServer(Data([0x14,0,0,4,0,1,0,4])) // idle Tickle after a desktop transition
        try await client.receive()
        XCTAssertEqual(wire.subscriptions, subscriptions+1)
        XCTAssertEqual(wire.fullRequests, requests)
        // DesktopSize followed by pixels in one update must replace the surface before decode.
        var resized = Data([0,0,0,2,0,0,0,0,0,3,0,1,255,255,255,33])
        resized += Data([0,0,0,0,0,3,0,1,0,0,0,0]) + Data(repeating: 25, count: 12)
        try wire.enqueueServer(resized)
        try await client.receive()
        XCTAssertEqual(client.framebuffer?.size, VNCSize(width: 3, height: 1))
        XCTAssertEqual(wire.fullRequests, requests+1)
        XCTAssertEqual(wire.subscriptions, subscriptions+2)
        XCTAssertFalse(wire.outboundEncodings.contains(1010))
        XCTAssertFalse(wire.outboundEncodings.contains(1110))
        try wire.enqueueServer(Data([0,0,0,1,0,0,0,0,0x4e,0x20,0,1,255,255,255,33]))
        do { try await client.receive(); XCTFail("Oversized resize must fail before allocating a surface") }
        catch { XCTAssertTrue(error is AppleStandardError) }
        XCTAssertEqual(client.framebuffer?.size, VNCSize(width: 3, height: 1))
    }
}

private final class SyntheticAppleDelegate: VNCConnectionDelegate {
    var pixelUpdates = 0
    func connection(_ connection: VNCConnection, stateDidChange connectionState: VNCConnection.ConnectionState) {}
    func connection(_ connection: VNCConnection, credentialFor authenticationType: VNCAuthenticationType,
                    completion: @escaping (VNCCredential?) -> Void) {
        completion(VNCUsernamePasswordCredential(username: "fixture", password: "synthetic-only"))
    }
    func connection(_ connection: VNCConnection, didCreateFramebuffer framebuffer: VNCFramebuffer) {}
    func connection(_ connection: VNCConnection, didResizeFramebuffer framebuffer: VNCFramebuffer) {}
    func connection(_ connection: VNCConnection, didUpdateFramebuffer framebuffer: VNCFramebuffer,
                    x: UInt16, y: UInt16, width: UInt16, height: UInt16) { pixelUpdates += 1 }
    func connection(_ connection: VNCConnection, didUpdateCursor cursor: VNCCursor) {}
}

/// Generated pixels and dummy credentials only. This is not a native-client capture.
private final class SyntheticAppleWire: NetworkConnection {
    var status: NetworkConnectionStatus { .ready }
    var isReady: Bool { true }
    private var incoming = Data("RFB 003.889\n".utf8)
    private var stage = 0
    private var key = Data()
    private var sender: AppleStandardRecords?
    private var receiver: AppleStandardRecords?
    private var encrypted = false
    private(set) var clientInit: UInt8 = 0
    private(set) var fullRequests = 0
    private(set) var subscriptions = 0
    private(set) var outboundEncodings: [Int32] = []
    private(set) var receivedInput = Data()
    private var initiallyZeroSized = false
    private var sentPixels = false
    init(initiallyZeroSized: Bool = false) { self.initiallyZeroSized = initiallyZeroSized }
    required init(settings: NetworkConnectionSettings) {}
    func setStatusUpdateHandler(_ handler: NetworkConnectionStatusUpdateHandler?) {}
    func cancel() {}
    func start(queue: DispatchQueue) {}
    func enqueueServer(_ body: Data) throws { incoming += try sender!.seal(body) }
    func read(minimumLength: Int, maximumLength: Int) async throws -> Data {
        guard !incoming.isEmpty else { throw AppleStandardError.invalidMessage }
        let result = Data(incoming.prefix(min(maximumLength, 3)))
        incoming = Data(incoming.dropFirst(result.count)); return result
    }
    func write(data: Data) async throws {
        if encrypted {
            let body = try receiver!.open(Data(data.dropFirst(2)))
            if body.first == 4 { receivedInput = body }
            if body.first == 3 {
                fullRequests += 1
                if initiallyZeroSized && !sentPixels {
                    sentPixels = true
                    try enqueueServer(Data([0,0,0,1,0,0,0,0,0,2,0,1,0,0,0,0,50,70,90,255,50,70,90,255]))
                }
            }
            if body.first == 9 || (body.first == 3 && body.count > 10 && body[10] == 9) { subscriptions += 1 }
            return
        }
        switch stage {
        case 0:
            XCTAssertEqual(data, Data("RFB 003.889\n".utf8)); incoming += Data([1,30]); stage = 1
        case 1:
            XCTAssertEqual(data, Data([30]))
            let prime = Data([0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xc9,0x0f,0xda,0xa2,0x21,0x68,0xc2,0x35])
            incoming += Data([0,2,0,16]) + prime + Data(repeating: 0, count: 15) + Data([2]); stage = 2
        case 2:
            XCTAssertEqual(data.count, 128); stage = 3
        case 3:
            key = Data(data.md5()); incoming += Data(repeating: 0, count: 4); stage = 4
        case 4:
            clientInit = data[0]
            let pixelFormat = Data([32,24,0,1,0,255,0,255,0,255,16,8,0,0,0,0])
            let name = Data([0,0]) + AppleStandardWire.be(UInt32(0)) + Data(repeating: 0, count: 16) + Data("Fixture\0".utf8)
            incoming += (initiallyZeroSized ? Data([0,0,0,0]) : Data([0,2,0,1])) + pixelFormat + AppleStandardWire.be(UInt32(name.count)) + name; stage = 5
        default:
            if data.first == 2 {
                let count = Int(data[2])*256 + Int(data[3])
                outboundEncodings = (0..<count).map { Int32(bitPattern: AppleStandardWire.u32(data, 4+$0*4)) }
            }
            if data == AppleStandardWire.encryptionRequest {
                let cipher = try AES(key: Array(key), blockMode: ECB(), padding: .noPadding)
                let sessionKey = Data(0..<16), iv = Data(16..<32)
                let payload = AppleStandardWire.be(UInt32(1)) + Data(try cipher.encrypt(Array(sessionKey))) + Data(try cipher.encrypt(Array(iv)))
                if initiallyZeroSized {
                    // Locked console announces geometry separately before encryption.
                    incoming += Data([0,0,0,1,0,0,0,0,0,2,0,1,255,255,255,33])
                }
                incoming += Data([0,0,0,1]) + Data(repeating: 0, count: 8) + AppleStandardWire.be(UInt32(1103)) + payload
                sender = try AppleStandardRecords(key: sessionKey, iv: iv)
                receiver = try AppleStandardRecords(key: sessionKey, iv: iv)
            }
            if data.first == 3 { fullRequests += 1 }
            if data == AppleStandardWire.encryptionAck {
                encrypted = true
                if initiallyZeroSized { return }
                let pixels = Data([0,0,0,1,0,0,0,0,0,2,0,1,0,0,0,0, 50,70,90,255,50,70,90,255])
                // A single framebuffer message split across two encrypted records.
                incoming += try sender!.seal(Data(pixels.prefix(7)))
                incoming += try sender!.seal(Data(pixels.dropFirst(7)))
            }
        }
    }
}
