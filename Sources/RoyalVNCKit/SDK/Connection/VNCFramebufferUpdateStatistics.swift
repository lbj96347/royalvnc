#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// One completely received and decoded update. Byte counts are RFB bytes, not TCP overhead.
public struct VNCFramebufferUpdateStatistics: Sendable {
    public let receivedBytes: UInt64
    public let transferAndDecodeSeconds: TimeInterval
    /// Encoding ID to bytes consumed by its rectangle headers and payloads, including pseudo encodings.
    public let encodingBytes: [Int64: UInt64]
    public let pixelRectangleCount: Int
    public let updatedPixels: UInt64
}

/// Optional observations only; callbacks must not block the receive/send loops.
public protocol VNCFramebufferStatisticsObserver: AnyObject {
    func framebufferUpdateRequested(incremental: Bool)
    func framebufferUpdateCompleted(_ statistics: VNCFramebufferUpdateStatistics)
}

/// Called once after all rectangles are painted, before the next update is requested.
public protocol VNCFramebufferCompletionObserver: AnyObject {
    func connection(_ connection: VNCConnection, didCompleteFramebufferUpdate framebuffer: VNCFramebuffer,
                    statistics: VNCFramebufferUpdateStatistics)
}

/// Serializes snapshots with whole update decoding, without blocking the input task.
actor VNCFramebufferAccess {
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !held { held = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty { held = false }
        else { waiters.removeFirst().resume() }
    }
}

public extension VNCConnection {
    /// The body runs synchronously with a complete framebuffer; do not retain its mutable surface.
    func withCompletedFramebuffer(_ body: @Sendable (VNCFramebuffer) -> Void) async {
        await framebufferAccess.acquire()
        if !Task.isCancelled, !state.disconnectRequested, let framebuffer { body(framebuffer) }
        await framebufferAccess.release()
    }
}
