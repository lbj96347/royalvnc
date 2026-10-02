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
