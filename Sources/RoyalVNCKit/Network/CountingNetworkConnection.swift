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
    var status: NetworkConnectionStatus { base.status }
    var isReady: Bool { base.isReady }
    func setStatusUpdateHandler(_ handler: NetworkConnectionStatusUpdateHandler?) { base.setStatusUpdateHandler(handler) }
    func cancel() { base.cancel() }
    func start(queue: DispatchQueue) { base.start(queue: queue) }
    func read(minimumLength: Int, maximumLength: Int) async throws -> Data {
        let started = DispatchTime.now().uptimeNanoseconds
        let data = try await base.read(minimumLength: minimumLength, maximumLength: maximumLength)
        lock.withLock {
            byteCount += UInt64(data.count)
            readNanoseconds += DispatchTime.now().uptimeNanoseconds - started
        }
        return data
    }
    func write(data: Data) async throws { try await base.write(data: data) }
}
