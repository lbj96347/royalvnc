import Foundation
import XCTest
@testable import RoyalVNCKit

final class ByteTransportTests: XCTestCase {
    func testInjectedTransportAccumulatesFragmentedReadsAndWritesInOrder() async throws {
        let stream = FixtureTransport(chunks: [Data([1]), Data([2, 3])])
        let connection = ByteTransportNetworkConnection(transport: stream)
        connection.start(queue: .global())
        XCTAssertTrue(connection.isReady)
        let bytes = try await connection.read(minimumLength: 3, maximumLength: 3)
        XCTAssertEqual(bytes, Data([1, 2, 3]))
        try await connection.write(data: Data([4, 5]))
        XCTAssertEqual(stream.writes, [Data([4, 5])])
        connection.cancel()
        XCTAssertTrue(stream.cancelled)
        XCTAssertFalse(connection.isReady)
        connection.start(queue: .global())
        XCTAssertFalse(connection.isReady)
    }

    func testEmptyOrOversizedReadFailsInsteadOfLoopingOrOverrunning() async throws {
        for bytes in [Data(), Data([1, 2])] {
            let connection = ByteTransportNetworkConnection(transport: FixtureTransport(chunks: [bytes]))
            do { _ = try await connection.read(minimumLength: 1, maximumLength: 1); XCTFail("Invalid read must fail") }
            catch {}
        }
    }
}

private final class FixtureTransport: VNCByteTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var chunks: [Data]
    private var sent: [Data] = []
    private var stopped = false
    var writes: [Data] { lock.withLock { sent } }
    var cancelled: Bool { lock.withLock { stopped } }
    init(chunks: [Data]) { self.chunks = chunks }
    func read(maximumLength: Int) async throws -> Data {
        lock.withLock { chunks.isEmpty ? Data() : chunks.removeFirst() }
    }
    func write(_ data: Data) async throws { lock.withLock { sent.append(data) } }
    func cancel() { lock.withLock { stopped = true } }
}
