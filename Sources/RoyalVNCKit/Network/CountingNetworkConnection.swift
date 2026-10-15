import Foundation
import Dispatch
#if canImport(Network)
import Network
#endif

/// Counts received RFB payload bytes once at the lowest read boundary (excludes TCP/IP overhead).
final class CountingNetworkConnection: NetworkConnection {
    private let base: any NetworkConnection
    private let lock = NSLock()
    private var byteCount: UInt64 = 0
    private var receiveRecords: AppleStandardRecords?
    private var sendRecords: AppleStandardRecords?
    private var plaintext = Data()
    var isAppleEncrypted: Bool { sendRecords != nil }
    func installAppleEncryption(payload: Data, wrapKey: Data) throws {
        let (key, iv) = try AppleStandardRecords.unwrap(payload, key: wrapKey)
        if let receiveRecords, let sendRecords {
            guard plaintext.isEmpty else { throw AppleStandardError.invalidMessage }
            try receiveRecords.rekey(key: key, iv: iv)
            try sendRecords.rekey(key: key, iv: iv)
        } else {
            receiveRecords = try AppleStandardRecords(key: key, iv: iv)
            sendRecords = try AppleStandardRecords(key: key, iv: iv)
        }
    }
    private var readNanoseconds: UInt64 = 0
    var readWaitNanoseconds: UInt64 { lock.withLock { readNanoseconds } }
    var receivedByteCount: UInt64 { lock.withLock { byteCount } }
    required init(settings: NetworkConnectionSettings) {
        #if canImport(Network)
        base = NWConnection(settings: settings)
        #else
        base = SocketNetworkConnection(settings: settings)
        #endif
    }
    init(base: any NetworkConnection) { self.base = base }
    var status: NetworkConnectionStatus { base.status }
    var isReady: Bool { base.isReady }
    func setStatusUpdateHandler(_ handler: NetworkConnectionStatusUpdateHandler?) { base.setStatusUpdateHandler(handler) }
    func cancel() { base.cancel() }
    func start(queue: DispatchQueue) { base.start(queue: queue) }
    func read(minimumLength: Int, maximumLength: Int) async throws -> Data {
        guard let receiveRecords else { return try await readWire(minimumLength: minimumLength, maximumLength: maximumLength) }
        guard minimumLength > 0, maximumLength >= minimumLength else { throw AppleStandardError.invalidMessage }
        if plaintext.isEmpty {
            let header = try await readWireExactly(2)
            let length = Int(header[0]) * 256 + Int(header[1])
            guard length >= 32, length <= 65520, length % 16 == 0 else { throw AppleStandardError.integrity }
            let ciphertext = try await readWireExactly(length)
            plaintext = try receiveRecords.open(ciphertext)
        }
        guard !plaintext.isEmpty else { throw AppleStandardError.invalidMessage }
        let result = Data(plaintext.prefix(maximumLength))
        plaintext = Data(plaintext.dropFirst(result.count))
        return result
    }
    private func readWireExactly(_ length: Int) async throws -> Data {
        var result = Data()
        while result.count < length {
            let chunk = try await readWire(minimumLength: 1, maximumLength: length-result.count)
            guard !chunk.isEmpty else { throw AppleStandardError.invalidMessage }
            result += chunk
        }
        return result
    }
    private func readWire(minimumLength: Int, maximumLength: Int) async throws -> Data {
        let started = DispatchTime.now().uptimeNanoseconds
        let data = try await base.read(minimumLength: minimumLength, maximumLength: maximumLength)
        lock.withLock {
            byteCount += UInt64(data.count)
            readNanoseconds += DispatchTime.now().uptimeNanoseconds - started
        }
        return data
    }
    func write(data: Data) async throws {
        guard let sendRecords else { return try await base.write(data: data) }
        var offset = 0
        while offset < data.count {
            let end = min(data.count, offset + 65498)
            try await base.write(data: sendRecords.seal(Data(data[offset..<end])))
            offset = end
        }
    }
}
