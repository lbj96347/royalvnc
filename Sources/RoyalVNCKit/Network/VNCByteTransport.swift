import Foundation
import Dispatch

/// Optional ordered byte transport. One reader and one writer; cancel must unblock pending I/O.
/// TCP remains the default for every existing VNCConnection initializer.
public protocol VNCByteTransport: AnyObject, Sendable {
    func read(maximumLength: Int) async throws -> Data
    func write(_ data: Data) async throws
    func cancel()
}

final class ByteTransportNetworkConnection: NetworkConnection {
    private let transport: any VNCByteTransport
    private let lock = NSLock()
    private var currentStatus: NetworkConnectionStatus = .setup
    private var handler: NetworkConnectionStatusUpdateHandler?
    required init(settings: NetworkConnectionSettings) { fatalError("A byte transport is required") }
    init(transport: any VNCByteTransport) { self.transport = transport }
    var status: NetworkConnectionStatus { lock.withLock { currentStatus } }
    var isReady: Bool { if case .ready = status { return true }; return false }
    func setStatusUpdateHandler(_ handler: NetworkConnectionStatusUpdateHandler?) { lock.withLock { self.handler = handler } }
    func start(queue: DispatchQueue) { transition(.ready) }
    func cancel() { transport.cancel(); transition(.cancelled) }
    func read(minimumLength: Int, maximumLength: Int) async throws -> Data {
        guard minimumLength > 0, maximumLength >= minimumLength else { throw VNCError.protocol(.invalidData) }
        var data = Data()
        while data.count < minimumLength {
            let chunk = try await transport.read(maximumLength: maximumLength - data.count)
            guard !chunk.isEmpty, chunk.count <= maximumLength - data.count else { throw VNCError.protocol(.invalidData) }
            data.append(chunk)
        }
        return data
    }
    func write(data: Data) async throws { try await transport.write(data) }
    private func transition(_ next: NetworkConnectionStatus) {
        let callback = lock.withLock { () -> NetworkConnectionStatusUpdateHandler? in
            if case .cancelled = currentStatus { return nil }
            currentStatus = next
            return handler
        }
        callback?(next)
    }
}
